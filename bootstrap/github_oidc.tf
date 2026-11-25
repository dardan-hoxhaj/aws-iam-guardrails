# GitHub Actions -> AWS without stored keys.
#
# 1. The OIDC provider tells AWS to trust tokens signed by GitHub.
# 2. Each role's trust policy says WHICH GitHub jobs may use it: only this
#    repo, and only pull requests (plan) or the protected environment (apply).
# 3. AWS returns credentials that expire after one hour.

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  github_repo_path = "repo:${var.github_owner}/${var.github_repo}"
  trail_bucket_arn = "arn:aws:s3:::${var.name_prefix}-cloudtrail-${local.account_id}"
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://${local.github_oidc_host}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

# ---------------------------------------------------------------- plan role

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-gha-plan"
  description          = "Read-only role for terraform plan on pull requests in ${var.github_owner}/${var.github_repo}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubPullRequestsOnly"
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = "${local.github_repo_path}:pull_request"
        }
      }
    }]
  })
}

data "aws_iam_policy_document" "plan" {
  #checkov:skip=CKV_AWS_356:Organizations, Identity Center and Identity Store ARNs contain IDs (org ID, SSO instance ID) that do not exist until the live stack is applied, and many of their List/Describe actions do not support resource-level permissions. Scoped by read-only action lists instead; tighten after first apply (see README "What's next").
  statement {
    sid = "ReadOrgAndIdentityCenter"
    actions = [
      "organizations:Describe*",
      "organizations:List*",
      "sso:Describe*",
      "sso:Get*",
      "sso:List*",
      "identitystore:Describe*",
      "identitystore:GetGroupId",
      "identitystore:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ListTrailsAndAnalyzers"
    actions   = ["cloudtrail:DescribeTrails", "access-analyzer:ListAnalyzers"]
    resources = ["*"]
  }

  statement {
    sid = "ReadProjectTrail"
    actions = [
      "cloudtrail:GetEventSelectors",
      "cloudtrail:GetInsightSelectors",
      "cloudtrail:GetTrail",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:ListTags",
    ]
    resources = ["arn:aws:cloudtrail:*:${local.account_id}:trail/${var.name_prefix}-*"]
  }

  statement {
    sid       = "ReadProjectAnalyzer"
    actions   = ["access-analyzer:GetAnalyzer", "access-analyzer:ListTagsForResource"]
    resources = ["arn:aws:access-analyzer:*:${local.account_id}:analyzer/${var.name_prefix}-*"]
  }

  statement {
    sid = "ReadTrailBucketConfig"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [local.trail_bucket_arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadStateObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  # terraform plan takes the state lock, so it must create and delete the
  # lock file. It cannot touch the state file itself.
  statement {
    sid       = "ManageLockFileOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# --------------------------------------------------------------- apply role

resource "aws_iam_role" "apply" {
  name                 = "${var.name_prefix}-gha-apply"
  description          = "Apply role for the protected ${var.github_apply_environment} environment in ${var.github_owner}/${var.github_repo}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubProtectedEnvironmentOnly"
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = "${local.github_repo_path}:environment:${var.github_apply_environment}"
        }
      }
    }]
  })
}

data "aws_iam_policy_document" "apply" {
  #checkov:skip=CKV_AWS_109:Managing IAM guardrails IS permissions management. Bounded by explicit action lists, IAM actions are limited to Identity Center role paths, and only the reviewer-protected environment can assume this role.
  #checkov:skip=CKV_AWS_111:Write actions are listed one by one per service. Organizations and Identity Center resources have no ARNs before the first apply, so those statements use "*".
  #checkov:skip=CKV_AWS_356:Same reason as CKV_AWS_111. CloudTrail, S3, Access Analyzer and IAM statements are scoped to this project's ARNs.
  # The plan role's read permissions, reused.
  source_policy_documents = [data.aws_iam_policy_document.plan.json]

  statement {
    sid = "ManageOrganizationGuardrails"
    actions = [
      "organizations:AttachPolicy",
      "organizations:CreateAccount",
      "organizations:CreateOrganization",
      "organizations:CreateOrganizationalUnit",
      "organizations:CreatePolicy",
      "organizations:DeleteOrganizationalUnit",
      "organizations:DeletePolicy",
      "organizations:DetachPolicy",
      "organizations:DisablePolicyType",
      "organizations:EnableAWSServiceAccess",
      "organizations:EnablePolicyType",
      "organizations:MoveAccount",
      "organizations:TagResource",
      "organizations:UntagResource",
      "organizations:UpdateOrganizationalUnit",
      "organizations:UpdatePolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageIdentityCenter"
    actions = [
      "sso:AttachManagedPolicyToPermissionSet",
      "sso:CreateAccountAssignment",
      "sso:CreatePermissionSet",
      "sso:DeleteAccountAssignment",
      "sso:DeletePermissionSet",
      "sso:DetachManagedPolicyFromPermissionSet",
      "sso:ProvisionPermissionSet",
      "sso:TagResource",
      "sso:UntagResource",
      "sso:UpdatePermissionSet",
      "identitystore:CreateGroup",
      "identitystore:DeleteGroup",
      "identitystore:UpdateGroup",
    ]
    resources = ["*"]
  }

  # Identity Center creates roles under this path in each target account.
  statement {
    sid = "IdentityCenterProvisionedRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:UpdateRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*"]
  }

  statement {
    sid = "IdentityCenterSamlProvider"
    actions = [
      "iam:CreateSAMLProvider",
      "iam:DeleteSAMLProvider",
      "iam:GetSAMLProvider",
      "iam:UpdateSAMLProvider",
    ]
    resources = ["arn:aws:iam::${local.account_id}:saml-provider/AWSSSO_*"]
  }

  statement {
    sid       = "ReadServiceLinkedRoles"
    actions   = ["iam:GetRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
  }

  statement {
    sid       = "ServiceLinkedRolesForManagedServices"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "access-analyzer.amazonaws.com",
        "cloudtrail.amazonaws.com",
        "organizations.amazonaws.com",
        "sso.amazonaws.com",
      ]
    }
  }

  statement {
    sid = "ManageProjectTrail"
    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:RemoveTags",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["arn:aws:cloudtrail:*:${local.account_id}:trail/${var.name_prefix}-*"]
  }

  statement {
    sid = "ManageTrailBucket"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:ListBucketVersions",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = [local.trail_bucket_arn]
  }

  statement {
    sid       = "EmptyTrailBucketOnTeardown"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${local.trail_bucket_arn}/*"]
  }

  statement {
    sid = "ManageProjectAnalyzer"
    actions = [
      "access-analyzer:CreateAnalyzer",
      "access-analyzer:DeleteAnalyzer",
      "access-analyzer:TagResource",
      "access-analyzer:UntagResource",
    ]
    resources = ["arn:aws:access-analyzer:*:${local.account_id}:analyzer/${var.name_prefix}-*"]
  }

  statement {
    sid       = "WriteState"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

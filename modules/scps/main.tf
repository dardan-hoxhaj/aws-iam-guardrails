# Service Control Policies (SCPs).
#
# An SCP never GRANTS anything. It sets the maximum permissions for every
# principal in the member accounts it is attached to, including account
# admins and the root user. An explicit Deny here beats any Allow in IAM.
#
# Policies are built with jsonencode() so the unit tests in tests/ can read
# them, and so the 5,120-character SCP size limit can be checked before apply.

locals {
  guardrails_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLeavingOrganization"
        Effect   = "Deny"
        Action   = ["organizations:LeaveOrganization"]
        Resource = "*"
      },
      {
        Sid    = "ProtectAuditTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:PutInsightSelectors",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
        ]
        Resource = "*"
      },
      {
        Sid      = "ProtectAccessAnalyzer"
        Effect   = "Deny"
        Action   = ["access-analyzer:DeleteAnalyzer"]
        Resource = "*"
      },
      {
        Sid      = "DenyMemberAccountRootUser"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = { "aws:PrincipalArn" = ["arn:aws:iam::*:root"] }
        }
      },
      {
        # People sign in through IAM Identity Center and get temporary
        # credentials. Long-lived IAM user keys are the #1 leaked secret.
        Sid      = "DenyLongLivedIamUserKeys"
        Effect   = "Deny"
        Action   = ["iam:CreateAccessKey", "iam:CreateUser"]
        Resource = "*"
      },
      {
        Sid      = "KeepEbsEncryptionOn"
        Effect   = "Deny"
        Action   = ["ec2:DisableEbsEncryptionByDefault"]
        Resource = "*"
      },
    ]
  }

  # Global services have no region (or live only in us-east-1), so they are
  # exempt via NotAction. Without this list, IAM, billing and support break.
  region_exempt_actions = [
    "account:*",
    "acm:*",
    "aws-marketplace:*",
    "budgets:*",
    "ce:*",
    "cloudfront:*",
    "cur:*",
    "directconnect:*",
    "ec2:DescribeRegions",
    "globalaccelerator:*",
    "health:*",
    "iam:*",
    "identitystore:*",
    "kms:*",
    "networkmanager:*",
    "organizations:*",
    "pricing:*",
    "route53:*",
    "route53domains:*",
    "s3:GetAccountPublic*",
    "s3:ListAllMyBuckets",
    "s3:PutAccountPublic*",
    "shield:*",
    "sso:*",
    "sts:*",
    "support:*",
    "trustedadvisor:*",
    "waf:*",
    "wafv2:*",
  ]

  region_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyOutsideAllowedRegions"
      Effect    = "Deny"
      NotAction = local.region_exempt_actions
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
      }
    }]
  }

  policies = {
    guardrails = {
      description = "Baseline guardrails: protect audit, block root and IAM user keys, stay in the org."
      content     = jsonencode(local.guardrails_policy)
    }
    region-restriction = {
      description = "Deny regional API calls outside ${join(", ", var.allowed_regions)}."
      content     = jsonencode(local.region_policy)
    }
  }

  # Every (policy, target) pair becomes one attachment.
  attachments = {
    for pair in setproduct(keys(local.policies), keys(var.target_ids)) :
    "${pair[0]}/${pair[1]}" => { policy = pair[0], target_id = var.target_ids[pair[1]] }
  }
}

resource "aws_organizations_policy" "this" {
  for_each = local.policies

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = each.value.content

  lifecycle {
    precondition {
      condition     = length(each.value.content) <= 5120
      error_message = "SCP ${each.key} is over the 5,120-character AWS limit."
    }
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = each.value.target_id
}

# DELIBERATELY INSECURE. Do not apply.
# CI runs checkov against this folder and EXPECTS it to fail. If checkov ever
# passes this file, the security gate is broken and the CI job fails.

data "aws_iam_policy_document" "admin_everything" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "admin_everything" {
  name   = "risky-admin-everything"
  policy = data.aws_iam_policy_document.admin_everything.json
}

# Trust policy that lets ANY GitHub repo assume the role.
resource "aws_iam_role" "any_github_repo" {
  name = "risky-any-github-repo"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = { "token.actions.githubusercontent.com:sub" = "repo:*" }
      }
    }]
  })
}

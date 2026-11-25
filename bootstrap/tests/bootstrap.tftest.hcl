# Unit tests: run with `terraform test` (no AWS account needed).
# The mock provider fakes AWS, so these check OUR logic, not AWS behavior.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  github_owner = "example-owner"
  github_repo  = "aws-iam-guardrails"
}

run "plan_role_trusts_only_pull_requests_from_this_repo" {
  command = apply

  assert {
    condition = (
      jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:example-owner/aws-iam-guardrails:pull_request"
    )
    error_message = "Plan role must trust only pull_request jobs from this exact repo."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"]
      == "sts.amazonaws.com"
    )
    error_message = "Plan role must check the token audience."
  }
}

run "apply_role_trusts_only_the_protected_environment" {
  command = apply

  assert {
    condition = (
      jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:example-owner/aws-iam-guardrails:environment:production"
    )
    error_message = "Apply role must trust only the protected production environment."
  }
}

run "trust_policies_never_use_wildcards" {
  command = apply

  assert {
    condition = alltrue([
      for role in [aws_iam_role.plan, aws_iam_role.apply] :
      !strcontains(role.assume_role_policy, "*")
    ])
    error_message = "A wildcard in a GitHub OIDC trust policy lets other repos or branches assume the role."
  }

  assert {
    condition     = aws_iam_role.plan.max_session_duration == 3600 && aws_iam_role.apply.max_session_duration == 3600
    error_message = "CI credentials should expire after one hour."
  }
}

run "state_bucket_name_is_derived_from_prefix_and_account" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "iam-guardrails-tfstate-111111111111"
    error_message = "Unexpected state bucket name."
  }
}

run "bad_prefix_is_rejected" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

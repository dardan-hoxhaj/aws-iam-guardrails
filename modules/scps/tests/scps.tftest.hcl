# Unit tests: run with `terraform test` (no AWS account needed).

mock_provider "aws" {}

variables {
  name_prefix     = "iam-guardrails"
  allowed_regions = ["us-east-1", "us-west-2"]
  target_ids = {
    Sandbox   = "ou-test-sandbox"
    Workloads = "ou-test-workloads"
  }
}

run "every_scp_fits_the_aws_size_limit" {
  command = plan

  assert {
    condition     = alltrue([for doc in values(output.policy_documents) : length(doc) <= 5120])
    error_message = "An SCP is over 5,120 characters."
  }
}

run "scps_only_deny" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for doc in values(output.policy_documents) :
      [for s in jsondecode(doc).Statement : s.Effect == "Deny"]
    ]))
    error_message = "These SCPs are deny-list guardrails; an Allow here would be a design change."
  }
}

run "audit_trail_cannot_be_stopped" {
  command = plan

  assert {
    condition = contains(
      [for s in jsondecode(output.policy_documents["guardrails"]).Statement : s.Sid],
      "ProtectAuditTrail"
    )
    error_message = "Guardrails must protect CloudTrail."
  }
}

run "region_policy_uses_the_allowed_regions" {
  command = plan

  assert {
    condition = (
      jsondecode(output.policy_documents["region-restriction"]).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"]
      == ["us-east-1", "us-west-2"]
    )
    error_message = "Region SCP does not match allowed_regions."
  }

  assert {
    condition = contains(
      jsondecode(output.policy_documents["region-restriction"]).Statement[0].NotAction,
      "iam:*"
    )
    error_message = "Global services like IAM must be exempt from the region deny."
  }
}

run "each_policy_is_attached_to_each_target" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 4
    error_message = "Expected 2 policies x 2 targets = 4 attachments."
  }
}

run "empty_region_list_is_rejected" {
  command = plan

  variables {
    allowed_regions = []
  }

  expect_failures = [var.allowed_regions]
}

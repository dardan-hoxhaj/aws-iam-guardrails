# Wiring tests for the live stack: run with `terraform test` (no AWS needed).

mock_provider "aws" {
  mock_resource "aws_organizations_organization" {
    defaults = {
      id                = "o-exampleorg1"
      master_account_id = "111111111111"
      roots             = [{ id = "r-root", arn = "arn:aws:organizations::111111111111:root/o-exampleorg1/r-root", name = "Root", policy_types = [] }]
    }
  }

  mock_resource "aws_organizations_organizational_unit" {
    defaults = { id = "ou-abcd-12345678" }
  }

  mock_resource "aws_organizations_account" {
    defaults = { id = "222222222222" }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = { arn = "arn:aws:sso:::permissionSet/ssoins-example/ps-example" }
  }

  mock_resource "aws_identitystore_group" {
    defaults = { group_id = "a1b2c3d4-1111-2222-3333-444455556666" }
  }

  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::example-bucket", id = "example-bucket", bucket = "example-bucket" }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-example"]
      identity_store_ids = ["d-example"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

run "scps_attach_to_ous_never_to_the_root" {
  command = apply

  assert {
    condition = alltrue([
      for a in module.scps.attachment_target_ids : startswith(a, "ou-")
    ])
    error_message = "SCPs must target OUs so a bad policy cannot lock out every account."
  }
}

run "without_sandbox_admins_only_get_the_management_account" {
  command = apply

  assert {
    condition     = output.sandbox_account_id == null
    error_message = "Sandbox account should be off by default."
  }

  assert {
    condition     = length(module.identity_center[0].assignment_keys) == 3
    error_message = "Expected 3 assignments (one per group) in the management account."
  }
}

run "with_sandbox_admins_get_the_sandbox_too" {
  command = apply

  variables {
    create_sandbox_account = true
    sandbox_account_email  = "sandbox@example.com"
  }

  assert {
    condition     = contains(module.identity_center[0].assignment_keys, "platform-admins/PlatformAdmin/sandbox")
    error_message = "Admins should be able to reach the sandbox account for the SCP drill."
  }
}

run "home_region_must_be_allowed" {
  command = plan

  variables {
    aws_region      = "eu-west-1"
    allowed_regions = ["us-east-1"]
  }

  expect_failures = [var.allowed_regions]
}

# AWS Organizations: the account running this becomes the MANAGEMENT account.
# Note: SCPs never restrict the management account itself, only member
# accounts. That is why this module can optionally create a sandbox member
# account to test the guardrails against.

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  aws_service_access_principals = [
    "access-analyzer.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "sso.amazonaws.com",
  ]

  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = toset(var.organizational_units)

  name      = each.value
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_account" "sandbox" {
  count = var.create_sandbox_account ? 1 : 0

  name              = "${var.name_prefix}-sandbox"
  email             = var.sandbox_account_email
  parent_id         = aws_organizations_organizational_unit.this[var.sandbox_ou_name].id
  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = true

  lifecycle {
    # AWS does not let you read back role_name after creation.
    ignore_changes = [role_name]

    precondition {
      condition     = try(length(var.sandbox_account_email) > 3, false) && contains(var.organizational_units, var.sandbox_ou_name)
      error_message = "Set sandbox_account_email, and make sure sandbox_ou_name is one of organizational_units."
    }
  }
}

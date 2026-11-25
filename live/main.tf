# Live stack: everything here is applied from the management account.

module "organization" {
  source = "../modules/organization"

  name_prefix            = var.name_prefix
  create_sandbox_account = var.create_sandbox_account
  sandbox_account_email  = var.sandbox_account_email
}

# SCPs go on OUs, not on the root, so the blast radius of a bad policy is
# limited to the accounts you deliberately moved into those OUs.
module "scps" {
  source = "../modules/scps"

  name_prefix     = var.name_prefix
  allowed_regions = var.allowed_regions
  target_ids = {
    Workloads = module.organization.ou_ids["Workloads"]
    Sandbox   = module.organization.ou_ids["Sandbox"]
  }
}

module "cloudtrail" {
  source = "../modules/cloudtrail"

  name_prefix          = var.name_prefix
  organization_id      = module.organization.organization_id
  log_retention_days   = var.cloudtrail_log_retention_days
  force_destroy_bucket = var.force_destroy_trail_bucket
}

module "access_analyzer" {
  source = "../modules/access-analyzer"

  name_prefix = var.name_prefix

  depends_on = [module.organization]
}

locals {
  # Accounts that receive Identity Center assignments, keyed by label.
  accounts = merge(
    { management = module.organization.management_account_id },
    var.create_sandbox_account ? { sandbox = module.organization.sandbox_account_id } : {},
  )
}

module "identity_center" {
  source = "../modules/identity-center"
  count  = var.enable_identity_center ? 1 : 0

  permission_sets = {
    ReadOnly = {
      description        = "See resources and configs, but not data inside them."
      session_duration   = "PT4H"
      managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
    }
    SecurityAudit = {
      description        = "Read security configuration across services."
      session_duration   = "PT4H"
      managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
    }
    PlatformAdmin = {
      description        = "Full admin, short sessions. Use only when ReadOnly is not enough."
      session_duration   = "PT1H"
      managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
    }
  }

  groups = {
    "platform-admins"   = "Break-glass and day-to-day platform administration."
    "security-auditors" = "Security reviews and audits."
    "readonly"          = "Anyone who needs to look, not touch."
  }

  accounts = local.accounts

  # Admins also get the sandbox, which is where the SCP drill happens.
  assignments = [
    { group = "readonly", permission_set = "ReadOnly", accounts = keys(local.accounts) },
    { group = "security-auditors", permission_set = "SecurityAudit", accounts = keys(local.accounts) },
    { group = "platform-admins", permission_set = "PlatformAdmin", accounts = keys(local.accounts) },
  ]

  depends_on = [module.organization]
}

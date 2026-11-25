# IAM Identity Center (single sign-on for AWS).
#
# Identity Center itself must be enabled once in the console (Terraform
# cannot turn on an organization instance). This module then manages:
#   - permission sets: named bundles of permissions, like job roles
#   - groups: people get access by group membership, never one by one
#   - assignments: "group X gets permission set Y in account Z"

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # One entry per (group, permission set, account) triple. Keys use account
  # LABELS (e.g. "management"), not IDs, because a new account's ID is not
  # known until apply and for_each keys must be known at plan time.
  assignments = merge([
    for a in var.assignments : {
      for label in a.accounts :
      "${a.group}/${a.permission_set}/${label}" => merge(a, { account_id = var.accounts[label] })
    }
  ]...)
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = each.value.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  #checkov:skip=CKV_AWS_274:PlatformAdmin is the intentional admin permission set: group-assigned, 1-hour sessions, every call logged by the org trail. ReadOnly and SecurityAudit cover daily work.
  for_each = var.permission_sets

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arn = each.value.managed_policy_arn
}

resource "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id

  depends_on = [aws_ssoadmin_managed_policy_attachment.this]
}

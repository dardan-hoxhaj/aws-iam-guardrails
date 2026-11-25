output "permission_set_arns" {
  description = "Map of permission set name to ARN."
  value       = { for k, p in aws_ssoadmin_permission_set.this : k => p.arn }
}

output "group_ids" {
  description = "Map of group name to Identity Store group ID."
  value       = { for k, g in aws_identitystore_group.this : k => g.group_id }
}

output "assignment_keys" {
  description = "group/permission-set/account keys for every assignment."
  value       = keys(aws_ssoadmin_account_assignment.this)
}

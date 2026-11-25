output "policy_ids" {
  description = "Map of SCP name to policy ID."
  value       = { for k, p in aws_organizations_policy.this : k => p.id }
}

output "policy_documents" {
  description = "Rendered SCP JSON, for review and tests."
  value       = { for k, p in local.policies : k => p.content }
}

output "attachment_target_ids" {
  description = "Every OU/account ID an SCP is attached to."
  value       = [for a in aws_organizations_policy_attachment.this : a.target_id]
}

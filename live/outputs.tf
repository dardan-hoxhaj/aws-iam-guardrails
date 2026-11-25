output "organization_id" {
  description = "Organization ID."
  value       = module.organization.organization_id
}

output "ou_ids" {
  description = "OU name to ID."
  value       = module.organization.ou_ids
}

output "sandbox_account_id" {
  description = "Sandbox member account ID (null if not created)."
  value       = module.organization.sandbox_account_id
}

output "scp_ids" {
  description = "SCP name to policy ID."
  value       = module.scps.policy_ids
}

output "cloudtrail_bucket" {
  description = "Where CloudTrail log files land."
  value       = module.cloudtrail.bucket_name
}

output "access_analyzer_arn" {
  description = "Organization Access Analyzer."
  value       = module.access_analyzer.analyzer_arn
}

output "permission_set_arns" {
  description = "Identity Center permission sets."
  value       = try(module.identity_center[0].permission_set_arns, {})
}

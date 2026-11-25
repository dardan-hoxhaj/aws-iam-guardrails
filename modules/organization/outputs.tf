output "organization_id" {
  description = "ID of the organization (o-xxxxxxxxxx)."
  value       = aws_organizations_organization.this.id
}

output "root_id" {
  description = "ID of the organization root (r-xxxx)."
  value       = aws_organizations_organization.this.roots[0].id
}

output "management_account_id" {
  description = "Account ID of the management account."
  value       = aws_organizations_organization.this.master_account_id
}

output "ou_ids" {
  description = "Map of OU name to OU ID."
  value       = { for name, ou in aws_organizations_organizational_unit.this : name => ou.id }
}

output "sandbox_account_id" {
  description = "Sandbox member account ID, or null if not created."
  value       = try(aws_organizations_account.sandbox[0].id, null)
}

variable "name_prefix" {
  description = "Short prefix for resource names."
  type        = string
}

variable "organizational_units" {
  description = "OUs to create directly under the organization root."
  type        = list(string)
  default     = ["Security", "Workloads", "Sandbox"]
}

variable "create_sandbox_account" {
  description = "Create one member account to test SCPs against. Closing it later takes up to 90 days (see docs/deploy.md)."
  type        = bool
  default     = false
}

variable "sandbox_account_email" {
  description = "Unique email for the sandbox account's root user. Keep it in terraform.tfvars, never in git."
  type        = string
  default     = null
  sensitive   = true
}

variable "sandbox_ou_name" {
  description = "Which OU the sandbox account goes into."
  type        = string
  default     = "Sandbox"
}

variable "aws_region" {
  description = "Home region. Must be where IAM Identity Center is enabled."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix for resource names. Must match the bootstrap stack."
  type        = string
  default     = "iam-guardrails"
}

variable "allowed_regions" {
  description = "Regions member accounts may use (region SCP). Must include aws_region."
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]

  validation {
    condition     = contains(var.allowed_regions, var.aws_region)
    error_message = "allowed_regions must include aws_region, or the region SCP would block your home region."
  }
}

variable "create_sandbox_account" {
  description = "Create a sandbox member account so the SCPs can be tested (SCPs never restrict the management account)."
  type        = bool
  default     = false
}

variable "sandbox_account_email" {
  description = "Unique email for the sandbox account root user. Set in terraform.tfvars or TF_VAR_sandbox_account_email; never commit it."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_identity_center" {
  description = "Manage Identity Center permission sets and groups. Enable Identity Center in the console first."
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Days to keep CloudTrail logs in S3."
  type        = number
  default     = 90
}

variable "force_destroy_trail_bucket" {
  description = "Allow terraform destroy to delete the CloudTrail bucket with logs in it (demo teardown only)."
  type        = bool
  default     = false
}

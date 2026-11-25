variable "aws_region" {
  description = "Region for the state bucket. Use the same region as the live stack."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix for every resource name in this project."
  type        = string
  default     = "iam-guardrails"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "Use 3-21 lowercase letters, digits or dashes, starting with a letter."
  }
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repo allowed to assume the CI roles."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the owner) allowed to assume the CI roles."
  type        = string
  default     = "aws-iam-guardrails"
}

variable "github_apply_environment" {
  description = "GitHub Actions environment whose jobs may assume the apply role. Protect it with a required reviewer."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the token.actions.githubusercontent.com OIDC provider."
  type        = bool
  default     = true
}

variable "force_destroy_state_bucket" {
  description = "Let terraform destroy delete the state bucket with old state versions in it. Set true only at final teardown."
  type        = bool
  default     = false
}

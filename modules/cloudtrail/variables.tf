variable "name_prefix" {
  description = "Short prefix for resource names."
  type        = string
}

variable "organization_id" {
  description = "Organization ID (o-xxxxxxxxxx); org trails write under AWSLogs/<org-id>/."
  type        = string
}

variable "log_retention_days" {
  description = "Days to keep CloudTrail log files in S3."
  type        = number
  default     = 90
}

variable "force_destroy_bucket" {
  description = "Let terraform destroy delete the log bucket even when it holds logs. Keep false in real use; true makes demo teardown one command."
  type        = bool
  default     = false
}

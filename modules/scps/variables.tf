variable "name_prefix" {
  description = "Short prefix for resource names."
  type        = string
}

variable "allowed_regions" {
  description = "Regions member accounts may use. Include the Identity Center region."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "Allow at least one region."
  }
}

variable "target_ids" {
  description = "Map of label => OU or account ID to attach every SCP to. Do not use the root ID until you have tested on an OU."
  type        = map(string)
}

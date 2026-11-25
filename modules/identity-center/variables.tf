variable "permission_sets" {
  description = "Permission sets keyed by name. session_duration is ISO 8601, e.g. PT1H."
  type = map(object({
    description        = string
    session_duration   = string
    managed_policy_arn = string
  }))
}

variable "groups" {
  description = "Identity Center groups keyed by name, value is the description. Add people to groups in the console."
  type        = map(string)
}

variable "accounts" {
  description = "Map of account label (e.g. management, sandbox) to AWS account ID."
  type        = map(string)
}

variable "assignments" {
  description = "Which group gets which permission set in which accounts (by label from var.accounts)."
  type = list(object({
    group          = string
    permission_set = string
    accounts       = list(string)
  }))

  validation {
    condition     = alltrue([for a in var.assignments : length(a.accounts) > 0])
    error_message = "Every assignment needs at least one account label."
  }
}

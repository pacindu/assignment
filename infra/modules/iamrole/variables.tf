variable "name" {
  description = "Name for the IAM role"
  type        = string
}

variable "description" {
  description = "Description for the IAM role"
  type        = string
  default     = ""
}

variable "assume_role_policy" {
  description = "JSON-encoded assume role (trust) policy document"
  type        = string
}

variable "managed_policy_arns" {
  description = "List of managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy name to JSON policy document"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

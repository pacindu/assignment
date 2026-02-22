variable "description" {
  description = "Description for the KMS key"
  type        = string
}

variable "alias_name" {
  description = "Alias name for the KMS key (must start with alias/)"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Number of days before the key is deleted after scheduling deletion"
  type        = number
  default     = 30
}

variable "enable_key_rotation" {
  description = "Whether to enable automatic key rotation"
  type        = bool
  default     = true
}

variable "key_policy" {
  description = "JSON-encoded key policy. If null, the default key policy is used."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

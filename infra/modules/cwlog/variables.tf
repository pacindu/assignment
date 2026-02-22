variable "name" {
  description = "Name of the CloudWatch log group"
  type        = string
}

variable "retention_in_days" {
  description = "Number of days to retain log events"
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for encrypting log data"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "Name of the CloudWatch log group"
  type        = string
}

variable "retention_in_days" {
  description = "Number of days to retain log events (CKV_AWS_338 requires >= 365)"
  type        = number
  default     = 365
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

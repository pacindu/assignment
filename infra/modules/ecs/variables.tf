variable "name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encrypting cluster secrets"
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group for ECS execute command logging"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

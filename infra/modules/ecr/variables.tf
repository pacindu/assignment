variable "name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for encryption"
  type        = string
}

variable "scan_on_push" {
  description = "Whether to scan images on push"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "lifecycle_policy" {
  description = "JSON lifecycle policy to apply to the repository. If null, no lifecycle policy is applied."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

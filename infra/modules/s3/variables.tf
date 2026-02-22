variable "bucket" {
  description = "Globally unique name for the S3 bucket"
  type        = string
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for SSE-KMS encryption. If null, SSE-S3 (AES256) is used."
  type        = string
  default     = null
}

variable "bucket_policy" {
  description = "JSON-encoded bucket policy. If null, no bucket policy is attached."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

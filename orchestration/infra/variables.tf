variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "prefix" {
  description = "Resource name prefix (e.g. ntt-gcc-production)"
  type        = string
}

variable "allowed_region" {
  description = "GCC-permitted AWS region enforced by the pre-flight Lambda"
  type        = string
  default     = "ap-southeast-1"
}

variable "expected_account_id" {
  description = "AWS account ID the pre-flight Lambda validates against. Leave empty to skip."
  type        = string
  default     = ""
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster managed by the deployment workflow"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service managed by the deployment workflow"
  type        = string
}

variable "ecs_task_family" {
  description = "ECS task definition family name"
  type        = string
}

variable "evidence_bucket_name" {
  description = "Name of the existing S3 bucket where evidence artefacts are uploaded"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for the application container"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Step Functions CloudWatch logs and S3 evidence"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_mb" {
  description = "Lambda memory allocation in MiB"
  type        = number
  default     = 256
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "family" {
  description = "Name of the task definition family"
  type        = string
}

variable "cpu" {
  description = "Number of CPU units (e.g. 256, 512, 1024)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MiB (e.g. 512, 1024)"
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "ARN of the IAM role that ECS uses to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the IAM role that the task itself can assume"
  type        = string
}

variable "container_definitions" {
  description = "JSON-encoded list of container definitions"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for the containers"
  type        = string
}

variable "region" {
  description = "AWS region where the task will run"
  type        = string
}

variable "cpu_architecture" {
  description = "CPU architecture for the Fargate task. X86_64 or ARM64."
  type        = string
  default     = "ARM64"
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

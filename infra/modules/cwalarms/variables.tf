variable "name_prefix" {
  description = "Prefix to prepend to all alarm names"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster to monitor"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service to monitor"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (used for 5xx metric dimensions)"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the Target Group (used for 5xx metric dimensions)"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to send alarm notifications to"
  type        = string
}

variable "cpu_threshold" {
  description = "CPU utilisation percentage threshold to trigger alarm"
  type        = number
  default     = 80
}

variable "memory_threshold" {
  description = "Memory utilisation percentage threshold to trigger alarm"
  type        = number
  default     = 80
}

variable "http_5xx_threshold" {
  description = "Number of ALB 5xx responses per minute to trigger alarm"
  type        = number
  default     = 10
}

variable "log_group_name" {
  description = "CloudWatch log group name to attach the ERROR log metric filter to"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

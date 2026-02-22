variable "name" {
  description = "Name of the ECS service"
  type        = string
}

variable "cluster_id" {
  description = "ID (ARN) of the ECS cluster to run the service in"
  type        = string
}

variable "task_definition_arn" {
  description = "ARN of the ECS task definition"
  type        = string
}

variable "desired_count" {
  description = "Desired number of tasks to run"
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "List of private subnet IDs to place the tasks in"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to the tasks"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the ALB target group to register tasks with"
  type        = string
}

variable "container_name" {
  description = "Name of the container to register with the target group"
  type        = string
}

variable "container_port" {
  description = "Port on the container to forward traffic to"
  type        = number
}

variable "capacity_provider_strategy" {
  description = "List of capacity provider strategy entries. Defaults to FARGATE_SPOT (primary) with FARGATE as fallback."
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = [
    { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 },
    { capacity_provider = "FARGATE",      weight = 1, base = 1 }
  ]
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent during deployment"
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Maximum percent during deployment"
  type        = number
  default     = 200
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_execute_command" {
  description = "To enable ECS exec"
  type = bool
  default = true
}

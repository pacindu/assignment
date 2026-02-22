variable "name" {
  description = "Name of the target group"
  type        = string
}

variable "port" {
  description = "Port on which targets receive traffic"
  type        = number
  default     = 80
}

variable "protocol" {
  description = "Protocol for targets (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

variable "vpc_id" {
  description = "ID of the VPC the targets reside in"
  type        = string
}

variable "target_type" {
  description = "Type of target (ip for Fargate, instance for EC2)"
  type        = string
  default     = "ip"
}

variable "health_check_path" {
  description = "HTTP path for the health check"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a health check response"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Consecutive successful health checks before considering the target healthy"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failed health checks before considering the target unhealthy"
  type        = number
  default     = 3
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a target"
  type        = number
  default     = 30
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

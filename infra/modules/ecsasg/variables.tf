variable "name_prefix" {
  description = "Prefix for auto scaling policy names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service to scale"
  type        = string
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 6
}

variable "cpu_target" {
  description = "Target average CPU utilisation percentage to maintain"
  type        = number
  default     = 70
}

variable "memory_target" {
  description = "Target average memory utilisation percentage to maintain"
  type        = number
  default     = 70
}

variable "scale_out_cooldown" {
  description = "Seconds to wait after a scale-out before another scale-out can occur"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds to wait after a scale-in before another scale-in can occur"
  type        = number
  default     = 300
}

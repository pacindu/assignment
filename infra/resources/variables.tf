variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "workspace_iam_roles" {
  description = "Map of workspace name to IAM role ARN to assume when provisioning resources"
  type        = map(string)
}

variable "name" {
  description = "Base name prefix — workspace name is appended automatically"
  type        = string
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of exactly 2 availability zones"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly 2 availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ (ALB, NAT Gateway)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ (ECS Fargate)"
  type        = list(string)
}

variable "secure_subnet_cidrs" {
  description = "CIDR blocks for secure subnets — one per AZ (databases, no internet)"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------
variable "container_port" {
  description = "Port the ECS container listens on"
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------
# ALB / ACM
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Primary domain name for the ACM certificate and ALB"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for ACM DNS validation. Set to null to skip auto-validation."
  type        = string
  default     = null
}

variable "alb_access_logs_bucket" {
  description = "Globally-unique S3 bucket name for ALB access logs (bucket is created by this stack)"
  type        = string
}

variable "health_check_path" {
  description = "HTTP path the ALB target group uses for ECS health checks"
  type        = string
  default     = "/health"
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------
variable "container_name" {
  description = "Name of the application container inside the task definition"
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Docker image URI for the application container (e.g. ECR URL or public image)"
  type        = string
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 / 512 / 1024 / 2048 / 4096)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "ecs_capacity_provider_strategy" {
  description = "Capacity provider strategy for the ECS service. Defaults to FARGATE_SPOT primary with FARGATE fallback."
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = [
    { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 },
    { capacity_provider = "FARGATE", weight = 1, base = 1 }
  ]
}

# -----------------------------------------------------------------------------
# ECS Auto Scaling
# -----------------------------------------------------------------------------
variable "asg_min_capacity" {
  description = "Minimum number of ECS tasks (floor for auto scaling)"
  type        = number
  default     = 1
}

variable "asg_max_capacity" {
  description = "Maximum number of ECS tasks (ceiling for auto scaling)"
  type        = number
  default     = 6
}

variable "asg_cpu_target" {
  description = "Target average CPU utilisation % to maintain via auto scaling"
  type        = number
  default     = 70
}

variable "asg_memory_target" {
  description = "Target average memory utilisation % to maintain via auto scaling"
  type        = number
  default     = 70
}

# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------
variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per IP before WAF blocks the source"
  type        = number
  default     = 2000
}

# -----------------------------------------------------------------------------
# Alarms
# -----------------------------------------------------------------------------
variable "alarm_email" {
  description = "Email address to subscribe to the SNS alarm topic. Set to null to skip email subscription."
  type        = string
  default     = null
}

variable "alarm_cpu_threshold" {
  description = "ECS CPU utilisation % that triggers the high-CPU alarm"
  type        = number
  default     = 80
}

variable "alarm_memory_threshold" {
  description = "ECS memory utilisation % that triggers the high-memory alarm"
  type        = number
  default     = 80
}

variable "alarm_5xx_threshold" {
  description = "Number of ALB 5xx responses per minute that triggers the alarm"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
variable "tags" {
  description = "A map of tags applied to all resources"
  type        = map(string)
  default     = {}
}


variable "enable_execute_command" {
  description = "To enable ECS exec"
  type        = bool
  default     = true
}
variable "name" {
  description = "Name of the Application Load Balancer"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs to place the ALB in"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to the ALB"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS listener"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the default target group for the HTTPS listener"
  type        = string
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
}

variable "access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb"
}

variable "idle_timeout" {
  description = "Idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the ALB (recommended for production)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

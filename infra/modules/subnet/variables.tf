variable "vpc_id" {
  description = "ID of the VPC to create subnets in"
  type        = string
}

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "availability_zones" {
  description = "List of exactly 2 availability zones"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly 2 availability zones must be specified."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ (ALB, NAT Gateway)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ (ECS Fargate, application tier)"
  type        = list(string)
}

variable "secure_subnet_cidrs" {
  description = "CIDR blocks for secure subnets — one per AZ (databases, no internet access)"
  type        = list(string)
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

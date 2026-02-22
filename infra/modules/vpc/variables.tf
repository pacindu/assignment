variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

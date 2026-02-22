variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "igw_id" {
  description = "ID of the Internet Gateway for public route tables"
  type        = string
}

variable "natgw_id" {
  description = "ID of the NAT Gateway for private route tables"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs to associate with the public route table"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to associate with private route tables"
  type        = list(string)
}

variable "secure_subnet_ids" {
  description = "List of secure subnet IDs — associated with an isolated route table (no internet, no NAT)"
  type        = list(string)
}

variable "name" {
  description = "Name prefix for route tables"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

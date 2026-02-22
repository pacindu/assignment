variable "vpc_id" {
  description = "ID of the VPC to attach the Internet Gateway to"
  type        = string
}

variable "name" {
  description = "Name for the Internet Gateway"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

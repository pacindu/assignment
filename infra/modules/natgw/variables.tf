variable "public_subnet_id" {
  description = "ID of the public subnet to place the NAT Gateway in"
  type        = string
}

variable "name" {
  description = "Name for the NAT Gateway and Elastic IP"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

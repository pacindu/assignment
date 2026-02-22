variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "name" {
  description = "Name for the Network ACL"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs to associate with this NACL"
  type        = list(string)
}

variable "ingress_rules" {
  description = "List of ingress rules for the NACL"
  type = list(object({
    rule_no    = number
    protocol   = string
    action     = string
    cidr_block = string
    from_port  = number
    to_port    = number
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rules for the NACL"
  type = list(object({
    rule_no    = number
    protocol   = string
    action     = string
    cidr_block = string
    from_port  = number
    to_port    = number
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

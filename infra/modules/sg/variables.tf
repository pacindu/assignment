variable "vpc_id" {
  description = "ID of the VPC to create the security group in"
  type        = string
}

variable "name" {
  description = "Name for the security group"
  type        = string
}

variable "description" {
  description = "Description for the security group"
  type        = string
}

variable "ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    security_group_id = optional(string, null)
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rules"
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    security_group_id = optional(string, null)
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

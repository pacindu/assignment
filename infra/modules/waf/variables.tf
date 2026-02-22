variable "name" {
  description = "Name for the WAF Web ACL and its CloudWatch metrics"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB to associate the Web ACL with"
  type        = string
}

variable "rate_limit" {
  description = "Maximum requests per 5-minute window per IP before blocking"
  type        = number
  default     = 2000
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "domain_name" {
  description = "Primary domain name for the certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names to add as SANs"
  type        = list(string)
  default     = []
}

variable "validation_method" {
  description = "Certificate validation method (DNS or EMAIL)"
  type        = string
  default     = "DNS"
}

variable "zone_id" {
  description = "Route53 hosted zone ID for DNS validation records (required when validation_method = DNS)"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

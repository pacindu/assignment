output "certificate_arn" {
  description = "The ARN of the ACM certificate"
  value       = aws_acm_certificate.this.arn
}

output "domain_name" {
  description = "The primary domain name of the certificate"
  value       = aws_acm_certificate.this.domain_name
}

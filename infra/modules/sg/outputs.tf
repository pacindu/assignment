output "sg_id" {
  description = "The ID of the security group"
  value       = aws_security_group.this.id
}

output "sg_arn" {
  description = "The ARN of the security group"
  value       = aws_security_group.this.arn
}

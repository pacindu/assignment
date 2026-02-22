output "public_subnet_ids" {
  description = "List of public subnet IDs (ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (ECS Fargate, application tier)"
  value       = aws_subnet.private[*].id
}

output "secure_subnet_ids" {
  description = "List of secure subnet IDs (databases, no internet access)"
  value       = aws_subnet.secure[*].id
}

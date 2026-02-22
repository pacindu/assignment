output "target_group_arn" {
  description = "The ARN of the target group"
  value       = aws_lb_target_group.this.arn
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the target group (used in CloudWatch metrics)"
  value       = aws_lb_target_group.this.arn_suffix
}

output "target_group_name" {
  description = "The name of the target group"
  value       = aws_lb_target_group.this.name
}

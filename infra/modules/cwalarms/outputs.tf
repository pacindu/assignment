output "cpu_alarm_arn" {
  description = "ARN of the ECS CPU high alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn
}

output "memory_alarm_arn" {
  description = "ARN of the ECS memory high alarm"
  value       = aws_cloudwatch_metric_alarm.memory_high.arn
}

output "alb_5xx_alarm_arn" {
  description = "ARN of the ALB 5xx high alarm"
  value       = aws_cloudwatch_metric_alarm.alb_5xx_high.arn
}

output "error_log_alarm_arn" {
  description = "ARN of the application error log alarm"
  value       = aws_cloudwatch_metric_alarm.error_log_alarm.arn
}

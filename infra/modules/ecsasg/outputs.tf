output "scaling_target_resource_id" {
  description = "Resource ID of the Application Auto Scaling target"
  value       = aws_appautoscaling_target.this.resource_id
}

output "cpu_policy_arn" {
  description = "ARN of the CPU target tracking scaling policy"
  value       = aws_appautoscaling_policy.cpu.arn
}

output "memory_policy_arn" {
  description = "ARN of the memory target tracking scaling policy"
  value       = aws_appautoscaling_policy.memory.arn
}

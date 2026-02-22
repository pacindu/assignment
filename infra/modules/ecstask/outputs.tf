output "task_definition_arn" {
  description = "The full ARN of the task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "The family of the task definition"
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "The revision number of the task definition"
  value       = aws_ecs_task_definition.this.revision
}

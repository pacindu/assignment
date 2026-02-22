output "state_machine_arn" {
  description = "ARN of the Step Functions deployment state machine"
  value       = aws_sfn_state_machine.deploy.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions deployment state machine"
  value       = aws_sfn_state_machine.deploy.name
}

output "lambda_preflight_arn" {
  description = "ARN of the pre-flight validation Lambda"
  value       = aws_lambda_function.preflight.arn
}

output "lambda_deploy_arn" {
  description = "ARN of the ECS deploy Lambda"
  value       = aws_lambda_function.deploy.arn
}

output "lambda_verify_arn" {
  description = "ARN of the post-deploy verification Lambda"
  value       = aws_lambda_function.verify.arn
}

output "lambda_rollback_arn" {
  description = "ARN of the ECS rollback Lambda"
  value       = aws_lambda_function.rollback.arn
}

output "lambda_evidence_arn" {
  description = "ARN of the evidence upload Lambda"
  value       = aws_lambda_function.evidence.arn
}

output "sfn_log_group_name" {
  description = "CloudWatch Log Group for Step Functions execution logs"
  value       = aws_cloudwatch_log_group.sfn.name
}

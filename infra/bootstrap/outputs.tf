output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket"
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.state_lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for state encryption"
  value       = aws_kms_key.state.arn
}

# output "cicd_role_arn" {
#   description = "ARN of the CI/CD IAM role (used in GitHub Actions workflows)"
#   value       = aws_iam_role.cicd.arn
# }

# output "github_oidc_provider_arn" {
#   description = "ARN of the GitHub Actions OIDC provider"
#   value       = aws_iam_openid_connect_provider.github.arn
# }

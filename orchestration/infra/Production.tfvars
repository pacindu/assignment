region  = "ap-southeast-1"
prefix  = "ntt-gcc-production"

# GCC constraints enforced by pre-flight Lambda
allowed_region      = "ap-southeast-1"
expected_account_id = "992382521824"

# ECS resources from Assignment 1 infra stack
ecs_cluster_name = "Ntt-Gcc-Production-Cluster"
ecs_service_name = "Ntt-Gcc-Production-Service"
ecs_task_family  = "Ntt-Gcc-Production-Task"

# Reuse the ALB access logs S3 bucket for evidence storage
evidence_bucket_name = "ntt-gcc-production-alb-logs-992382521824"

# Application log group
log_group_name = "/ecs/app/ntt-gcc-production"

# KMS key from Assignment 1 (used for Step Functions logs + S3 KMS encryption)
kms_key_arn = "arn:aws:kms:ap-southeast-1:992382521824:alias/ntt-gcc-production-Ecs"

# Lambda sizing
lambda_timeout   = 60
lambda_memory_mb = 256

tags = {
  Project            = "GCC"
  Environment        = "Production"
  Owner              = "NTT"
  CostCenter         = "NTT"
  Terraform          = "True"
  DataClassification = "Internal"
}

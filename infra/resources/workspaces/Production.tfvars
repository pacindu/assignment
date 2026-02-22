region = "ap-southeast-1"

container_port = 80

# IAM role assumed by Terraform for this workspace
# Replace ACCOUNT_ID with your AWS account ID (run: aws sts get-caller-identity)
workspace_iam_roles = {
  Production = "arn:aws:iam::992382521824:role/TerraformRole"
}

name = "ntt-gcc"

# -----------------------------------------------------------------------------
# Networking — 10.0.0.0/16 split across 3 tiers, 2 AZs
# -----------------------------------------------------------------------------
vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b",
]

# Public — ALB, NAT Gateway
public_subnet_cidrs = [
  "10.0.1.0/24", # ap-southeast-1a
  "10.0.2.0/24", # ap-southeast-1b
]

# Private — ECS Fargate (outbound via NAT)
private_subnet_cidrs = [
  "10.0.11.0/24", # ap-southeast-1a
  "10.0.12.0/24", # ap-southeast-1b
]

# Secure — databases, no internet access
secure_subnet_cidrs = [
  "10.0.21.0/24", # ap-southeast-1a
  "10.0.22.0/24", # ap-southeast-1b
]

# -----------------------------------------------------------------------------
# ALB / ACM
# -----------------------------------------------------------------------------
# TODO: replace with your actual domain (must be in the Route53 hosted zone below)
domain_name = "app.ntt.demodevops.net"

# Route53 hosted zone ID for automatic ACM DNS validation
# Set to null to skip — you will need to create the CNAME record manually
route53_zone_id = "Z008900124T77D0IKD8U6"

# S3 bucket for ALB access logs (created by this stack; must be globally unique)
alb_access_logs_bucket = "ntt-gcc-production-alb-logs-992382521824"

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------
# ECR repository is created by this stack; on first deploy use a bootstrap image
# then update to the ECR URL after the repository exists and an image has been pushed
container_image = "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com/ntt-gcc-production-app:latest"

container_name = "app"
task_cpu       = 256
task_memory    = 512
desired_count  = 1

# -----------------------------------------------------------------------------
# ECS Auto Scaling
# -----------------------------------------------------------------------------
asg_min_capacity  = 1
asg_max_capacity  = 2
asg_cpu_target    = 50
asg_memory_target = 50

# -----------------------------------------------------------------------------
# Alarms
# -----------------------------------------------------------------------------
alarm_email            = null # Set to an email address to receive alarm notifications
alarm_cpu_threshold    = 75
alarm_memory_threshold = 75
alarm_5xx_threshold    = 5

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
tags = {
  Project            = "GCC"
  Environment        = "Production"
  Owner              = "NTT"
  CostCenter         = "NTT"
  Terraform          = "True"
  DataClassification = "Internal"
}

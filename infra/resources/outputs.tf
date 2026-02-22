# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, NAT Gateway)"
  value       = module.subnets.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (ECS Fargate)"
  value       = module.subnets.private_subnet_ids
}

output "secure_subnet_ids" {
  description = "IDs of the secure subnets (databases, no internet)"
  value       = module.subnets.secure_subnet_ids
}

# -----------------------------------------------------------------------------
# Gateways
# -----------------------------------------------------------------------------
output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = module.igw.igw_id
}

output "natgw_id" {
  description = "ID of the NAT Gateway"
  value       = module.natgw.natgw_id
}

output "nat_public_ip" {
  description = "Public IP of the NAT Gateway Elastic IP"
  value       = module.natgw.eip_public_ip
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.route_tables.public_route_table_id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = module.route_tables.private_route_table_ids
}

output "secure_route_table_ids" {
  description = "IDs of the secure route tables (no internet)"
  value       = module.route_tables.secure_route_table_ids
}

# -----------------------------------------------------------------------------
# NACLs
# -----------------------------------------------------------------------------
output "nacl_public_id" {
  description = "ID of the public NACL"
  value       = module.nacl_public.acl_id
}

output "nacl_private_id" {
  description = "ID of the private NACL"
  value       = module.nacl_private.acl_id
}

output "nacl_secure_id" {
  description = "ID of the secure NACL"
  value       = module.nacl_secure.acl_id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
output "sg_alb_id" {
  description = "ID of the ALB security group"
  value       = module.sg_alb.sg_id
}

output "sg_ecs_id" {
  description = "ID of the ECS security group"
  value       = module.sg_ecs.sg_id
}

# -----------------------------------------------------------------------------
# ACM
# -----------------------------------------------------------------------------
output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = module.acm.certificate_arn
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route53 alias records)"
  value       = module.alb.alb_zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = module.alb.https_listener_arn
}

output "target_group_arn" {
  description = "ARN of the ECS target group"
  value       = module.tg.target_group_arn
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "ECR repository URL (use as base image URI in CI/CD)"
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.cluster_arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_service.service_name
}

output "ecs_task_definition_arn" {
  description = "ARN of the latest ECS task definition revision"
  value       = module.ecs_task.task_definition_arn
}

output "ecs_exec_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.iam_exec_role.role_arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = module.iam_task_role.role_arn
}

# -----------------------------------------------------------------------------
# ECS Auto Scaling
# -----------------------------------------------------------------------------
output "ecs_asg_cpu_policy_arn" {
  description = "ARN of the ECS CPU target tracking auto scaling policy"
  value       = module.ecs_asg.cpu_policy_arn
}

output "ecs_asg_memory_policy_arn" {
  description = "ARN of the ECS memory target tracking auto scaling policy"
  value       = module.ecs_asg.memory_policy_arn
}

# -----------------------------------------------------------------------------
# Alarms
# -----------------------------------------------------------------------------
output "sns_alarm_topic_arn" {
  description = "ARN of the SNS topic that receives all alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "alarm_ecs_cpu_arn" {
  description = "ARN of the ECS CPU high alarm"
  value       = module.cwalarms.cpu_alarm_arn
}

output "alarm_ecs_memory_arn" {
  description = "ARN of the ECS memory high alarm"
  value       = module.cwalarms.memory_alarm_arn
}

output "alarm_alb_5xx_arn" {
  description = "ARN of the ALB 5xx high alarm"
  value       = module.cwalarms.alb_5xx_alarm_arn
}

output "alarm_error_log_arn" {
  description = "ARN of the application ERROR log alarm"
  value       = module.cwalarms.error_log_alarm_arn
}

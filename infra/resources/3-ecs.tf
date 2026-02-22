# -----------------------------------------------------------------------------
# ECS stack: KMS, CloudWatch Logs, ECR, IAM roles, Cluster, Task, Service
# Capacity strategy: FARGATE_SPOT (primary) + FARGATE (fallback, base=1)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# KMS — shared CMK for ECS exec encryption, CW log groups, and ECR
# -----------------------------------------------------------------------------
module "kms_ecs" {
  source = "../modules/kms"

  description = "CMK for ECS cluster, CloudWatch logs, and ECR"
  alias_name  = "alias/${local.prefix}-Ecs"
  tags        = var.tags

  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
module "cwlog_ecs_exec" {
  source = "../modules/cwlog"

  name              = "/ecs/exec/${local.prefix}"
  retention_in_days = 365
  kms_key_arn       = module.kms_ecs.key_arn
  tags              = var.tags
}

module "cwlog_app" {
  source = "../modules/cwlog"

  name              = "/ecs/app/${local.prefix}"
  retention_in_days = 365
  kms_key_arn       = module.kms_ecs.key_arn
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# ECR — container image repository (KMS-encrypted, immutable tags)
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../modules/ecr"

  name        = lower("${local.prefix}-app")
  kms_key_arn = module.kms_ecs.key_arn
  tags        = var.tags

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM — ECS task execution role
# Allows ECS to pull images from ECR, write logs, and decrypt via KMS
# -----------------------------------------------------------------------------
module "iam_exec_role" {
  source = "../modules/iamrole"

  name        = "${local.prefix}-Ecs-ExecRole"
  description = "ECS task execution role - ECR pull, CloudWatch logs, KMS decrypt"
  tags        = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policies = {
    kms-decrypt = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource = module.kms_ecs.key_arn
      }]
    })
  }
}

# -----------------------------------------------------------------------------
# IAM — ECS task role
# Assumed by the running container — grants ECS exec (SSM) and KMS access
# -----------------------------------------------------------------------------
module "iam_task_role" {
  source = "../modules/iamrole"

  name        = "${local.prefix}-Ecs-TaskRole"
  description = "ECS task role - ECS exec (SSM) permissions"
  tags        = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  inline_policies = {
    ecs-exec = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:GenerateDataKey*"]
          Resource = module.kms_ecs.key_arn
        }
      ]
    })
  }
}

# -----------------------------------------------------------------------------
# ECS Cluster — Container Insights enabled, exec command encrypted via KMS
# FARGATE and FARGATE_SPOT capacity providers registered on the cluster
# -----------------------------------------------------------------------------
module "ecs_cluster" {
  source = "../modules/ecs"

  name           = "${local.prefix}-Cluster"
  kms_key_arn    = module.kms_ecs.key_arn
  log_group_name = module.cwlog_ecs_exec.log_group_name
  tags           = var.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition — Fargate, awsvpc networking, awslogs driver
# -----------------------------------------------------------------------------
module "ecs_task" {
  source = "../modules/ecstask"

  family             = "${local.prefix}-Task"
  cpu                = var.task_cpu
  memory             = var.task_memory
  execution_role_arn = module.iam_exec_role.role_arn
  task_role_arn      = module.iam_task_role.role_arn
  log_group_name     = module.cwlog_app.log_group_name
  region             = var.region
  tags               = var.tags

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.cwlog_app.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }

      readonlyRootFilesystem = false
    }
  ])
}

# -----------------------------------------------------------------------------
# ECS Service — Fargate Spot (primary) + Fargate (fallback, base=1)
# Tasks run in private subnets, registered with the ALB target group
# -----------------------------------------------------------------------------
module "ecs_service" {
  source = "../modules/ecsservice"

  name                   = "${local.prefix}-Service"
  cluster_id             = module.ecs_cluster.cluster_id
  task_definition_arn    = module.ecs_task.task_definition_arn
  desired_count          = var.desired_count
  subnet_ids             = module.subnets.private_subnet_ids
  security_group_ids     = [module.sg_ecs.sg_id]
  target_group_arn       = module.tg.target_group_arn
  container_name         = var.container_name
  container_port         = var.container_port
  enable_execute_command = var.enable_execute_command
  tags                   = var.tags

  # Override capacity strategy if needed; defaults to FARGATE_SPOT(w=3) + FARGATE(w=1,base=1)
  capacity_provider_strategy = var.ecs_capacity_provider_strategy
}

# -----------------------------------------------------------------------------
# ECS Application Auto Scaling — CPU + Memory target tracking
# Scales desired_count between asg_min_capacity and asg_max_capacity
# -----------------------------------------------------------------------------
module "ecs_asg" {
  source = "../modules/ecsasg"

  name_prefix   = local.prefix
  cluster_name  = module.ecs_cluster.cluster_name
  service_name  = module.ecs_service.service_name
  min_capacity  = var.asg_min_capacity
  max_capacity  = var.asg_max_capacity
  cpu_target    = var.asg_cpu_target
  memory_target = var.asg_memory_target
}



resource "aws_route53_record" "ecs" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
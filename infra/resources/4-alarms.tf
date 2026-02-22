# -----------------------------------------------------------------------------
# Alarms stack: KMS, SNS topic, CloudWatch alarms
# Monitors: ECS CPU, ECS Memory, ALB 5xx errors, Application ERROR log count
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# KMS — CMK for SNS topic encryption
# CloudWatch must be allowed to GenerateDataKey to publish to encrypted topics
# -----------------------------------------------------------------------------
module "kms_sns" {
  source = "../modules/kms"

  description = "CMK for SNS alarm notifications topic"
  alias_name  = "alias/${local.prefix}-Sns"
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
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt"
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
# SNS Topic — alarm notifications (KMS-encrypted)
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name              = "${local.prefix}-Alarms"
  kms_master_key_id = module.kms_sns.key_arn

  tags = merge(var.tags, {
    Name = "${local.prefix}-Alarms"
  })
}

resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountPublish"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:AddPermission",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish",
          "sns:Receive",
          "sns:RemovePermission",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:TagResource",
          "sns:UntagResource"
        ]
        Resource = aws_sns_topic.alarms.arn
      },
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription — only created when alarm_email is set
resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------
module "cwalarms" {
  source = "../modules/cwalarms"

  name_prefix             = local.prefix
  ecs_cluster_name        = module.ecs_cluster.cluster_name
  ecs_service_name        = module.ecs_service.service_name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.tg.target_group_arn_suffix
  log_group_name          = module.cwlog_app.log_group_name
  sns_topic_arn           = aws_sns_topic.alarms.arn
  cpu_threshold           = var.alarm_cpu_threshold
  memory_threshold        = var.alarm_memory_threshold
  http_5xx_threshold      = var.alarm_5xx_threshold
  tags                    = var.tags
}

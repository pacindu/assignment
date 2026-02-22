# -----------------------------------------------------------------------------
# ALB stack: ACM certificate, S3 access logs bucket, Target Group, ALB
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# S3 — ALB access logs bucket
# ALB access logs are delivered by the ELB service using SSE-S3 only;
# SSE-KMS is not supported for ALB log delivery.
# -----------------------------------------------------------------------------
module "s3_alb_logs" {
  source = "../modules/s3"

  bucket        = var.alb_access_logs_bucket
  force_destroy = true
  tags          = merge(var.tags, { Name = "${local.prefix}-Alb-Logs" })

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.alb_access_logs_bucket}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
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
# ACM Certificate — DNS-validated (auto-validates when zone_id is provided)
# Set route53_zone_id = null to skip auto-validation (manual CNAME required)
# -----------------------------------------------------------------------------
module "acm" {
  source = "../modules/acm"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  zone_id                   = var.route53_zone_id
  tags                      = var.tags
}

# -----------------------------------------------------------------------------
# Target Group — IP-type for ECS Fargate
# -----------------------------------------------------------------------------
module "tg" {
  source = "../modules/tg"

  name              = "${local.prefix}-Tg"
  port              = var.container_port
  protocol          = "HTTP"
  vpc_id            = module.vpc.vpc_id
  target_type       = "ip"
  health_check_path = var.health_check_path
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# HTTP listener  : 301 redirect → HTTPS
# HTTPS listener : TLS-terminate → forward to target group
# -----------------------------------------------------------------------------
module "alb" {
  source = "../modules/alb"

  name               = "${local.prefix}-Alb"
  subnet_ids         = module.subnets.public_subnet_ids
  security_group_ids = [module.sg_alb.sg_id]
  certificate_arn    = module.acm.certificate_arn
  target_group_arn   = module.tg.target_group_arn
  access_logs_bucket = module.s3_alb_logs.bucket_id
  access_logs_prefix = "alb"
  tags               = var.tags

  depends_on = [module.s3_alb_logs]
}

# -----------------------------------------------------------------------------
# WAF — Web ACL with AWS managed rules + rate limiting, associated to the ALB
# Rules: IP reputation (10), OWASP core (20), known bad inputs (30), rate (40)
# -----------------------------------------------------------------------------
module "waf" {
  source = "../modules/waf"

  name       = "${local.prefix}-Waf"
  alb_arn    = module.alb.alb_arn
  rate_limit = var.waf_rate_limit
  tags       = var.tags
}

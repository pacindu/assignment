#checkov:skip=CKV_AWS_91:False positive — WAF is associated with this ALB in the waf module via aws_wafv2_web_acl_association; checkov cannot resolve cross-module associations
#checkov:skip=CKV2_AWS_28:False positive — WAF is associated with this ALB in the waf module via aws_wafv2_web_acl_association; checkov cannot resolve cross-module associations
resource "aws_lb" "this" {
  name                       = var.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = var.security_group_ids
  subnets                    = var.subnet_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  # Security hardening: drop invalid HTTP headers
  drop_invalid_header_fields = true

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.access_logs_prefix
    enabled = true
  }

  tags = var.tags
}

# HTTP listener — redirects all HTTP traffic to HTTPS (no plain-text traffic)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener — terminates TLS, forwards to the target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }
}

terraform {
  required_version = ">= 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.33.0"
    }
  }
}

# -----------------------------------------------------------------------------
# WAF v2 Web ACL — REGIONAL scope (attached to ALB)
# Rules (evaluated in priority order):
#   10  AWSManagedRulesAmazonIpReputationList  — block known malicious IPs / bots
#   20  AWSManagedRulesCommonRuleSet           — OWASP core (SQLi, XSS, LFI …)
#   30  AWSManagedRulesKnownBadInputsRuleSet   — Log4Shell, Spring4Shell, etc.
#   40  RateLimit                              — block IPs exceeding rate_limit req/5 min
# Default action: ALLOW (rules only block on match)
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # --- IP Reputation List ---------------------------------------------------
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-IpReputation"
      sampled_requests_enabled   = true
    }
  }

  # --- OWASP Core Rule Set --------------------------------------------------
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # --- Known Bad Inputs (Log4Shell, Spring4Shell, etc.) --------------------
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # --- Rate Limiting --------------------------------------------------------
  rule {
    name     = "RateLimit"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Associate the Web ACL with the ALB
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# -----------------------------------------------------------------------------
# WAF logging — CloudWatch log group (name must start with "aws-waf-logs-")
# -----------------------------------------------------------------------------
#checkov:skip=CKV_AWS_158:KMS encryption for WAF log groups requires a dedicated key policy granting waf.amazonaws.com access; a separate KMS module would add complexity disproportionate to the risk
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = 365

  tags = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn
}

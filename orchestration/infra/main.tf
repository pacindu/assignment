terraform {
  required_version = ">= 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.33.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

# ===========================================================================
# Lambda source archives — zipped at plan time from the ../lambda/ directory
# ===========================================================================

data "archive_file" "preflight" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/preflight"
  output_path = "${path.module}/build/preflight.zip"
}

data "archive_file" "deploy" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/deploy"
  output_path = "${path.module}/build/deploy.zip"
}

data "archive_file" "verify" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/verify"
  output_path = "${path.module}/build/verify.zip"
}

data "archive_file" "rollback" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/rollback"
  output_path = "${path.module}/build/rollback.zip"
}

data "archive_file" "evidence" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/evidence"
  output_path = "${path.module}/build/evidence.zip"
}

# ===========================================================================
# IAM — Lambda execution role
# ===========================================================================

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.prefix}-orchestration-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = var.tags
}

# Basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline policy for ECS, CloudWatch Logs, S3, STS, KMS access
data "aws_iam_policy_document" "lambda_permissions" {
  # ECS actions needed by deploy, rollback, and preflight handlers
  statement {
    sid    = "EcsReadWrite"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeClusters",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # Pass roles required to register a new task definition revision
  statement {
    sid    = "PassRoleForEcs"
    effect = "Allow"
    actions = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # CloudWatch Logs — filter for ERROR events (verify handler)
  statement {
    sid    = "CwLogsFilter"
    effect = "Allow"
    actions = [
      "logs:FilterLogEvents",
      "logs:DescribeLogGroups",
    ]
    resources = [
      "arn:aws:logs:${var.region}:*:log-group:${var.log_group_name}",
      "arn:aws:logs:${var.region}:*:log-group:${var.log_group_name}:*",
    ]
  }

  # S3 — evidence upload (evidence handler)
  statement {
    sid    = "S3EvidenceUpload"
    effect = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.evidence_bucket_name}/deployment-evidence/*",
    ]
  }

  # STS — account ID validation (preflight handler)
  statement {
    sid    = "StsGetCallerIdentity"
    effect = "Allow"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # KMS — decrypt for ECS task role/execution role, encrypt S3 evidence
  statement {
    sid    = "KmsForLambda"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.prefix}-orchestration-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ===========================================================================
# IAM — Step Functions execution role
# ===========================================================================

data "aws_iam_policy_document" "sfn_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.prefix}-orchestration-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "sfn_permissions" {
  # Invoke all orchestration Lambda functions
  statement {
    sid    = "InvokeLambda"
    effect = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.preflight.arn,
      aws_lambda_function.deploy.arn,
      aws_lambda_function.verify.arn,
      aws_lambda_function.rollback.arn,
      aws_lambda_function.evidence.arn,
    ]
  }

  # CloudWatch Logs delivery for Step Functions execution logging
  statement {
    sid    = "CwLogsDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutLogEvents",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  # KMS for Step Functions execution logs
  statement {
    sid    = "KmsForSfn"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.prefix}-orchestration-sfn-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_permissions.json
}

# ===========================================================================
# CloudWatch Log Group for Step Functions
# ===========================================================================

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.prefix}-deploy"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ===========================================================================
# Lambda functions
# ===========================================================================

locals {
  lambda_common = {
    role    = aws_iam_role.lambda.arn
    runtime = "python3.12"
    timeout = var.lambda_timeout
    memory  = var.lambda_memory_mb
    env = {
      ALLOWED_REGION      = var.allowed_region
      EXPECTED_ACCOUNT_ID = var.expected_account_id
      POWERTOOLS_LOG_LEVEL = "INFO"
    }
  }
}

resource "aws_lambda_function" "preflight" {
  function_name    = "${var.prefix}-orchestration-preflight"
  description      = "Pre-flight validation: region constraint, account ID, ECS cluster tags"
  role             = local.lambda_common.role
  runtime          = local.lambda_common.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.preflight.output_path
  source_code_hash = data.archive_file.preflight.output_base64sha256
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory

  environment {
    variables = local.lambda_common.env
  }

  tags = var.tags
}

resource "aws_lambda_function" "deploy" {
  function_name    = "${var.prefix}-orchestration-deploy"
  description      = "ECS deploy: register new task definition revision, update service"
  role             = local.lambda_common.role
  runtime          = local.lambda_common.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.deploy.output_path
  source_code_hash = data.archive_file.deploy.output_base64sha256
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory

  environment {
    variables = local.lambda_common.env
  }

  tags = var.tags
}

resource "aws_lambda_function" "verify" {
  function_name    = "${var.prefix}-orchestration-verify"
  description      = "Post-deploy verification: HTTP health, security headers, CloudWatch error scan"
  role             = local.lambda_common.role
  runtime          = local.lambda_common.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.verify.output_path
  source_code_hash = data.archive_file.verify.output_base64sha256
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory

  environment {
    variables = local.lambda_common.env
  }

  tags = var.tags
}

resource "aws_lambda_function" "rollback" {
  function_name    = "${var.prefix}-orchestration-rollback"
  description      = "ECS rollback: revert service to previous task definition revision"
  role             = local.lambda_common.role
  runtime          = local.lambda_common.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.rollback.output_path
  source_code_hash = data.archive_file.rollback.output_base64sha256
  # Rollback waits for ECS stability — needs a longer timeout
  timeout          = 360
  memory_size      = local.lambda_common.memory

  environment {
    variables = local.lambda_common.env
  }

  tags = var.tags
}

resource "aws_lambda_function" "evidence" {
  function_name    = "${var.prefix}-orchestration-evidence"
  description      = "Evidence upload: build audit JSON and PUT to S3"
  role             = local.lambda_common.role
  runtime          = local.lambda_common.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.evidence.output_path
  source_code_hash = data.archive_file.evidence.output_base64sha256
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory

  environment {
    variables = local.lambda_common.env
  }

  tags = var.tags
}

# ===========================================================================
# Step Functions State Machine
# ===========================================================================

resource "aws_sfn_state_machine" "deploy" {
  name     = "${var.prefix}-deploy"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  # ASL definition with actual Lambda ARNs substituted
  definition = jsonencode({
    Comment = "NTT GCC — Self-Healing Deployment Workflow"
    StartAt = "PreflightValidation"
    States = {
      PreflightValidation = {
        Type       = "Task"
        Resource   = aws_lambda_function.preflight.arn
        ResultPath = "$.preflight"
        Next       = "PreflightCheck"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "UploadEvidencePreflightFailed"
        }]
      }

      PreflightCheck = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.preflight.passed"
          BooleanEquals = true
          Next          = "DeployApp"
        }]
        Default = "UploadEvidencePreflightFailed"
      }

      DeployApp = {
        Type       = "Task"
        Resource   = aws_lambda_function.deploy.arn
        ResultPath = "$.deploy"
        Next       = "WaitForStability"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "UploadEvidenceDeployFailed"
        }]
      }

      WaitForStability = {
        Type    = "Wait"
        Seconds = 60
        Next    = "PostDeployVerification"
      }

      PostDeployVerification = {
        Type       = "Task"
        Resource   = aws_lambda_function.verify.arn
        ResultPath = "$.verification"
        Next       = "VerificationCheck"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "Rollback"
        }]
      }

      VerificationCheck = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.verification.passed"
          BooleanEquals = true
          Next          = "UploadEvidenceSuccess"
        }]
        Default = "Rollback"
      }

      Rollback = {
        Type       = "Task"
        Resource   = aws_lambda_function.rollback.arn
        ResultPath = "$.rollback"
        Next       = "UploadEvidenceRollback"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "RollbackFailed"
        }]
      }

      UploadEvidenceSuccess = {
        Type     = "Task"
        Resource = aws_lambda_function.evidence.arn
        Parameters = {
          outcome   = "SUCCESS"
          "context.$" = "$"
        }
        ResultPath = "$.evidence"
        Next       = "DeploymentSucceeded"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "DeploymentSucceeded"
        }]
      }

      UploadEvidenceRollback = {
        Type     = "Task"
        Resource = aws_lambda_function.evidence.arn
        Parameters = {
          outcome   = "ROLLBACK_COMPLETE"
          "context.$" = "$"
        }
        ResultPath = "$.evidence"
        Next       = "DeploymentFailed"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "DeploymentFailed"
        }]
      }

      UploadEvidencePreflightFailed = {
        Type     = "Task"
        Resource = aws_lambda_function.evidence.arn
        Parameters = {
          outcome   = "PREFLIGHT_FAILED"
          "context.$" = "$"
        }
        ResultPath = "$.evidence"
        Next       = "DeploymentFailed"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "DeploymentFailed"
        }]
      }

      UploadEvidenceDeployFailed = {
        Type     = "Task"
        Resource = aws_lambda_function.evidence.arn
        Parameters = {
          outcome   = "DEPLOY_FAILED"
          "context.$" = "$"
        }
        ResultPath = "$.evidence"
        Next       = "DeploymentFailed"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "DeploymentFailed"
        }]
      }

      DeploymentSucceeded = {
        Type = "Succeed"
      }

      DeploymentFailed = {
        Type  = "Fail"
        Error = "DEPLOYMENT_FAILED"
        Cause = "Deployment failed or rolled back. See evidence artefact in S3 for details."
      }

      RollbackFailed = {
        Type  = "Fail"
        Error = "ROLLBACK_FAILED"
        Cause = "Post-deploy verification failed AND automated rollback also failed. Manual intervention required."
      }
    }
  })

  tags = var.tags
}

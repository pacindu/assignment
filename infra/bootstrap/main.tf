terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.33.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

#checkov:skip=CKV_AWS_109:kms:* on resource * is required for the root account KMS key admin statement — standard AWS pattern to prevent key lockout
#checkov:skip=CKV_AWS_111:kms:* write access on resource * is required for the root account KMS key admin statement — standard AWS pattern
#checkov:skip=CKV_AWS_356:resource * in a KMS key policy refers to the key itself, not all AWS resources — checkov false positive
data "aws_iam_policy_document" "state_kms" {
  # Root account full admin — prevents key lockout
  statement {
    sid    = "RootAdminAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }


# CI/CD pipeline role — encrypt and decrypt state files
#statement {
#  sid    = "CICDRoleAccess"
#  effect = "Allow"

#  principals {
#    type        = "AWS"
#    identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cicd_role_name}"]
#  }

# actions = [
#    "kms:GenerateDataKey",
#    "kms:GenerateDataKeyWithoutPlaintext",
#    "kms:Decrypt",
#    "kms:DescribeKey",
#  ]
#
#  resources = ["*"]
#}



}

# # GitHub Actions OIDC provider — allows GitHub Actions to assume IAM roles without static credentials
# resource "aws_iam_openid_connect_provider" "github" {
#   url             = "https://token.actions.githubusercontent.com"
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

#   tags = var.tags
# }

# # Trust policy — only allows the specific repo's workflows to assume this role
# data "aws_iam_policy_document" "cicd_trust" {
#   statement {
#     sid     = "GitHubOIDCTrust"
#     effect  = "Allow"
#     actions = ["sts:AssumeRoleWithWebIdentity"]

#     principals {
#       type        = "Federated"
#       identifiers = [aws_iam_openid_connect_provider.github.arn]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = "token.actions.githubusercontent.com:aud"
#       values   = ["sts.amazonaws.com"]
#     }

#     condition {
#       test     = "StringLike"
#       variable = "token.actions.githubusercontent.com:sub"
#       values   = ["repo:${var.github_org}/${var.github_repo}:*"]
#     }
#   }
# }

# CI/CD IAM role
# resource "aws_iam_role" "cicd" {
#   name               = var.cicd_role_name
#   description        = "Assumed by GitHub Actions via OIDC for Terraform and application deployments"
#   assume_role_policy = data.aws_iam_policy_document.cicd_trust.json

#   tags = var.tags
# }

# AdministratorAccess — full AWS access for Terraform deployments
# resource "aws_iam_role_policy_attachment" "cicd_admin" {
#   role       = aws_iam_role.cicd.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# Inline policy — Terraform state access (S3 + DynamoDB + KMS)
# resource "aws_iam_role_policy" "cicd_state" {
#   name = "terraform-state-access"
#   role = aws_iam_role.cicd.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "StateS3Access"
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject",
#           "s3:DeleteObject",
#           "s3:ListBucket",
#           "s3:GetBucketVersioning",
#         ]
#         Resource = [
#           aws_s3_bucket.state.arn,
#           "${aws_s3_bucket.state.arn}/*",
#         ]
#       },
#       {
#         Sid    = "StateDynamoDBLock"
#         Effect = "Allow"
#         Action = [
#           "dynamodb:GetItem",
#           "dynamodb:PutItem",
#           "dynamodb:DeleteItem",
#           "dynamodb:DescribeTable",
#         ]
#         Resource = aws_dynamodb_table.state_lock.arn
#       },
#       {
#         Sid    = "StateKMSAccess"
#         Effect = "Allow"
#         Action = [
#           "kms:GenerateDataKey",
#           "kms:GenerateDataKeyWithoutPlaintext",
#           "kms:Decrypt",
#           "kms:DescribeKey",
#         ]
#         Resource = aws_kms_key.state.arn
#       },
#     ]
#   })
# }

# KMS key for encrypting the state bucket and DynamoDB table
resource "aws_kms_key" "state" {
  description             = "KMS key for Terraform state bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.state_kms.json

  tags = var.tags
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

# S3 bucket for Terraform state
#checkov:skip=CKV_AWS_18:Access logging for the state bucket would require a separate logging bucket, adding circular dependency risk
#checkov:skip=CKV_AWS_144:Cross-region replication is not required for the Terraform state bucket in this assignment
#checkov:skip=CKV2_AWS_62:S3 event notifications are not required for the Terraform state bucket
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "abort-failed-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

data "aws_iam_policy_document" "state_bucket" {
  # Deny any request not using HTTPS
  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Deny PutObject requests that do not use the bucket KMS key (i.e. unencrypted uploads)
  statement {
    sid    = "DenyUnencryptedUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.state.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "state_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}

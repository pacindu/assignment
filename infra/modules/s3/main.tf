#checkov:skip=CKV_AWS_18:Access logging requires a dedicated logging bucket; enabling would create a circular dependency in this module design
#checkov:skip=CKV_AWS_144:Cross-region replication adds significant cost and is not required for this workload
#checkov:skip=CKV2_AWS_62:S3 event notifications are not required for this workload
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name = var.bucket
  })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = var.kms_key_arn != null ? true : false

    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "expire-objects"
    status = "Enabled"

    expiration {
      days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy != null ? 1 : 0

  bucket     = aws_s3_bucket.this.id
  policy     = var.bucket_policy
  depends_on = [aws_s3_bucket_public_access_block.this]
}

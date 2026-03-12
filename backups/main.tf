#1. Provider Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2" # Change to your preferred region
  profile = "root-account"
}

# 1. Define the S3 Bucket
resource "aws_s3_bucket" "truenas_backup" {
  bucket = "home.derek-crew.com-data.backups" # Must be globally unique
}

# 2. Create the IAM User for TrueNAS
resource "aws_iam_user" "truenas_user" {
  name = "truenas-s3-backup-user"
}

# 3. Generate Access Keys (To be entered into TrueNAS)
resource "aws_iam_access_key" "truenas_keys" {
  user = aws_iam_user.truenas_user.name
}

# 4. Create the Policy (Permissions for TrueNAS)
resource "aws_iam_user_policy" "truenas_policy" {
  name = "TrueNASBackupPolicy"
  user = aws_iam_user.truenas_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. Permission to see the list of ALL buckets in the UI/CLI
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.truenas_backup.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = ["${aws_s3_bucket.truenas_backup.arn}/*"]
      }
    ]
  })
}

# 1. Create the Secret container
resource "aws_secretsmanager_secret" "truenas_creds" {
  name        = "truenas/backup_credentials"
  description = "Access keys for TrueNAS S3 backup user"
}

# 2. Store the Access and Secret keys as a JSON object
resource "aws_secretsmanager_secret_version" "truenas_creds_val" {
  secret_id = aws_secretsmanager_secret.truenas_creds.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.truenas_keys.id
    secret_access_key = aws_iam_access_key.truenas_keys.secret
  })
}

# Update the S3 bucket to enable versioning
resource "aws_s3_bucket_versioning" "truenas_versioning" {
  bucket = aws_s3_bucket.truenas_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Add complex Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "backup_retention" {
  bucket = aws_s3_bucket.truenas_backup.id

  rule {
    id     = "archive_old_backups"
    status = "Enabled"

    # Add this empty filter block to resolve the warning
    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }
}
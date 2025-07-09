terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example_bucket" {
  # bucket = "my-tf-ci-test-bucket-unique-name" # Bucket names must be unique.
  # To make this runnable, let's use bucket_prefix which is more flexible for unique names.
  bucket_prefix = "tf-ci-test-bucket-"

  tags = {
    Name        = "My CI Test Bucket"
    Environment = "Dev"
    Terraform   = "true"
  }
}

# Deliberately insecure S3 bucket for tfsec/checkov to find
resource "aws_s3_bucket" "insecure_example_bucket" {
  bucket_prefix = "tf-ci-insecure-bucket-"
  # Missing: server_side_encryption_configuration
  # Missing: versioning
  # Missing: logging
  # Public access block might be okay by default depending on provider version, but explicit is better.

  # To make it clearly insecure for tfsec:
  acl = "public-read" # This is a major security issue.

  tags = {
    Name        = "My Insecure CI Test Bucket"
    Environment = "Dev"
    Terraform   = "true"
    Secure      = "false" # Self-documenting insecurity
  }
}


output "example_bucket_name" {
  value = aws_s3_bucket.example_bucket.bucket
}

output "insecure_bucket_name" {
  value = aws_s3_bucket.insecure_example_bucket.bucket
}

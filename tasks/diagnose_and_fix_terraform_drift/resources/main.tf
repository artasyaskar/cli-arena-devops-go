terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
  tags   = var.common_tags
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_role" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = var.common_tags

  # Inline policy for simplicity in this example
  inline_policy {
    name = "S3ReadOnlyAccess"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ],
          Effect   = "Allow",
          Resource = [
            aws_s3_bucket.data_bucket.arn,
            "${aws_s3_bucket.data_bucket.arn}/*"
          ]
        }
      ]
    })
  }
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = var.iam_instance_profile_name
  role = aws_iam_role.app_role.name
  tags = var.common_tags # Instance profiles themselves don't support tags via AWS API/Terraform directly here
                         # Tags on instance profiles are not a common drift point handled by TF.
                         # The association with a role is key.
}



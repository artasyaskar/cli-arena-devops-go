# This file should be created by the user/agent as per the task.
# Content for the IAM role in the Target Account (222222222222)

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.cicd_principal_arn] # ARN of the user/role in the CI/CD account (111111111111)
    }
    # Optional: Add condition for ExternalId for enhanced security
    # condition {
    #   test     = "StringEquals"
    #   variable = "sts:ExternalId"
    #   values   = ["some-unique-external-id"]
    # }
  }
}

resource "aws_iam_role" "deploy_role" {
  name               = var.deploy_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "IAM Role for CI/CD pipeline to deploy resources in this (Target) account."
  tags               = var.tags
}

data "aws_iam_policy_document" "deploy_permissions_policy_doc" {
  statement {
    actions = [
      "s3:ListAllMyBuckets", # Allows listing all buckets in the account
      "s3:ListBucket",       # Allows listing objects in a specific bucket (requires bucket ARN in Resource)
      "s3:GetBucketLocation" # Often needed with s3:ListBucket
    ]
    effect    = "Allow"
    resources = ["*"] # s3:ListAllMyBuckets requires "*"
    # For s3:ListBucket, you might specify particular buckets if known:
    # Example: "arn:aws:s3:::my-target-app-bucket", "arn:aws:s3:::my-target-app-bucket/*"
  }

  # Add another statement for more granular S3 access if needed, or other services.
  # For this task, ListAllMyBuckets is sufficient for the s3 ls test.
}

resource "aws_iam_policy" "deploy_permissions_policy" {
  name        = "${var.deploy_role_name}-PermissionsPolicy"
  description = "Policy granting permissions for CI/CD deployments."
  policy      = data.aws_iam_policy_document.deploy_permissions_policy_doc.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "deploy_role_attachment" {
  role       = aws_iam_role.deploy_role.name
  policy_arn = aws_iam_policy.deploy_permissions_policy.arn
}

output "deploy_role_arn" {
  description = "ARN of the created IAM role for CI/CD in the Target account."
  value       = aws_iam_role.deploy_role.arn
}

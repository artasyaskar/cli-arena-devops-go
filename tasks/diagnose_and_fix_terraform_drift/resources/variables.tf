variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name to ensure uniqueness"
  type        = string
  default     = "tf-drift-test-bucket"
}

variable "iam_role_name" {
  description = "Name for the IAM role"
  type        = string
  default     = "TerraformDriftTestRole"
}

variable "iam_instance_profile_name" {
  description = "Name for the IAM instance profile"
  type        = string
  default     = "TerraformDriftTestInstanceProfile"
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "Test"
    Project     = "TerraformDrift"
    ManagedBy   = "Terraform"
  }
}

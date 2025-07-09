variable "aws_region" {
  description = "AWS region for the S3 backend and dummy AWS resource"
  type        = string
  default     = "us-east-1"
}

variable "s3_backend_bucket_name" {
  description = "Name of the S3 bucket for Terraform state (must be globally unique)"
  type        = string
  # Default will be set by setup script using a random suffix to ensure uniqueness
  # default     = "tf-s3-backend-test-bucket-unique-value"
}

variable "s3_backend_key" {
  description = "Path to the state file in the S3 bucket"
  type        = string
  default     = "terraform.tfstate"
}

variable "s3_backend_dynamodb_table" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-locks"
}

variable "gcp_project_id" {
  description = "Google Cloud Project ID for GCS backend"
  type        = string
  default     = "your-gcp-project-id" # User should replace this or have it pre-configured
}

variable "gcp_region" {
  description = "Google Cloud Region for GCS bucket (if regional)"
  type        = string
  default     = "US-CENTRAL1" # Example region
}

variable "gcs_backend_bucket_name" {
  description = "Name for the GCS bucket for Terraform state (must be globally unique)"
  type        = string
  # User will define this bucket name as part of the task
  # default     = "tf-gcs-backend-test-bucket-unique-value"
}

variable "gcs_backend_prefix" {
  description = "Prefix (folder path) for the state file in the GCS bucket"
  type        = string
  default     = "terraform/state" # Example prefix
}

variable "enable_gcs_test_pet_creation" {
  description = "Flag to enable creation of the random_pet resource for testing GCS backend"
  type        = bool
  default     = false
}

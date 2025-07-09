variable "aws_region" {
  description = "AWS region for the S3 backend and dummy AWS resource"
  type        = string
  default     = "us-east-1"
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

variable "enable_gcs_test_pet_creation" {
  description = "Flag to enable creation of the random_pet resource for testing GCS backend"
  type        = bool
  default     = false
}

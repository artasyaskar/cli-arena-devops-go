# This file initially defines the S3 backend.
# The user's task is to modify this file to use a GCS backend.

terraform {
  required_version = ">= 0.12"
  backend "s3" {
    # Configuration will be dynamically inserted by setup_initial_s3_backend.sh
    # to ensure unique bucket names for testing.
    # bucket         = "placeholder-s3-bucket-name" # To be replaced by script
    # key            = "terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "placeholder-dynamo-table-name" # To be replaced
    # encrypt        = true
  }
}

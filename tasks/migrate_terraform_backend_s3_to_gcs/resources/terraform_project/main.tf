terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Assuming AWS CLI is configured, or using LocalStack with environment variables
  # For LocalStack, specific endpoint configurations might be needed here if not globally set.
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Assuming gcloud CLI is configured, or using service account JSON through GOOGLE_APPLICATION_CREDENTIALS
}

resource "random_id" "example_suffix" {
  byte_length = 4
}

resource "null_resource" "example" {
  triggers = {
    data = "This is a sample resource whose state needs to be migrated. Suffix: ${random_id.example_suffix.hex}"
  }
  lifecycle {
    prevent_destroy = false # Allow easy cleanup for testing
  }
}

output "example_trigger_data" {
  value = null_resource.example.triggers.data
}

# This resource will be added after migration to test the new GCS backend
resource "random_pet" "gcs_test_pet" {
  keepers = {
    # This ensures the resource is planned/applied only if explicitly uncommented or added
    # For the task, the user might add this to test the GCS backend.
    # For verify.sh, we will add it programmatically.
    enabled = var.enable_gcs_test_pet_creation
  }
  length = 2
}

output "gcs_test_pet_name" {
  value = var.enable_gcs_test_pet_creation ? random_pet.gcs_test_pet.id : "not_created"
}

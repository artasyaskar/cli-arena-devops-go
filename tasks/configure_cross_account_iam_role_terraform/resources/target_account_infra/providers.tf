terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend configuration for this part of the project (Target Account)
  # For simplicity in the task, we'll use local backend.
  # In a real setup, this would be a remote backend specific to the Target account.
  backend "local" {
    path = "target_account.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  # This provider block assumes credentials for the "Target Account" (e.g., 222222222222)
  # are configured in the environment where Terraform runs.
  # For testing, this might involve setting AWS_PROFILE or temporary credentials.
  # alias = "target" # Not strictly needed if this is the only provider block in this config set
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Using a recent version
    }
  }
  # Using local backend for simplicity in this task.
  backend "local" {
    path = "debug_dependencies.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  # Assumes AWS CLI is configured (e.g., via environment variables, shared credentials file, or EC2 instance profile).
  # For LocalStack, additional endpoint configurations might be needed here if not set globally.
  # default_tags {
  #   tags = {
  #     TerraformTask = "DebugDependencies"
  #   }
  # }
}

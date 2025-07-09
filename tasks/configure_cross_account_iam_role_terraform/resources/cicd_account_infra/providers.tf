terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend configuration for this part of the project (CI/CD Account)
  # For simplicity, using local backend.
  backend "local" {
    path = "cicd_account.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  # This provider block assumes credentials for the "CI/CD Account" (e.g., 111111111111)
  # are configured in the environment.
  # alias = "cicd" # Not strictly needed
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "project_name" {
  description = "A name prefix for resources to ensure some uniqueness and context"
  type        = string
  default     = "tf-debug"
}

variable "common_tags" {
  description = "Common tags to apply to all taggable resources"
  type        = map(string)
  default = {
    Environment = "dev-debug"
    Task        = "TerraformDependencyDebug"
    ManagedBy   = "Terraform"
  }
}

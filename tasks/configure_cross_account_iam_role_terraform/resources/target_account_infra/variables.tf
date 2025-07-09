variable "aws_region" {
  description = "AWS region for resources in the Target account"
  type        = string
  default     = "us-east-1"
}

variable "target_account_id" {
  description = "AWS Account ID of the Target account"
  type        = string
  default     = "222222222222" # Mocked Target Account ID
}

variable "cicd_principal_arn" {
  description = "ARN of the IAM principal (user/role) in the CI/CD account that is allowed to assume the role"
  type        = string
  default     = "arn:aws:iam::111111111111:user/cicd_user" # Mocked CI/CD user ARN from account 111111111111
}

variable "deploy_role_name" {
  description = "Name for the IAM role to be created in the Target account for CI/CD deployments"
  type        = string
  default     = "CICDDeployRole"
}

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "CrossAccountTest"
    Project     = "CICD"
    ManagedBy   = "Terraform"
  }
}

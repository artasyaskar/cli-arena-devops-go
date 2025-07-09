variable "aws_region" {
  description = "AWS region for resources in the CI/CD account"
  type        = string
  default     = "us-east-1"
}

variable "target_deploy_role_arn" {
  description = "ARN of the 'CICDDeployRole' in the Target account (output from target_account_infra)"
  type        = string
  # This value will be passed in by the setup_accounts.sh script or solution.sh
  # No default here as it's dynamically obtained.
}

variable "assume_role_policy_name" {
  description = "Name for the IAM policy that allows assuming the role in the target account"
  type        = string
  default     = "AssumeTargetAccountRolePolicy"
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

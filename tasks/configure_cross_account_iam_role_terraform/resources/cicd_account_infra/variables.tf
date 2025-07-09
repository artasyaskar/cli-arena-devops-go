variable "aws_region" {
  description = "AWS region for resources in the CI/CD account"
  type        = string
  default     = "us-east-1"
}

variable "cicd_account_id" {
  description = "AWS Account ID of the CI/CD account (source)"
  type        = string
  default     = "111111111111" # Mocked CI/CD Account ID
}

variable "cicd_principal_name" {
  description = "Name of the IAM user/role in the CI/CD account that will assume the role in the target account (e.g., 'cicd_user')"
  type        = string
  default     = "cicd_user" # This is the entity to attach the policy to.
                            # For this task, we assume this user/role already exists or is simulated.
                            # The Terraform config will create a policy and (optionally) attach it.
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

# This file should be created by the user/agent as per the task.
# Content for the IAM policy in the CI/CD Account (111111111111)

data "aws_iam_policy_document" "assume_target_role_policy_doc" {
  statement {
    actions   = ["sts:AssumeRole"]
    effect    = "Allow"
    resources = [var.target_deploy_role_arn] # ARN of CICDDeployRole in Target Account (222222222222)
  }
}

resource "aws_iam_policy" "assume_target_role_policy" {
  name        = var.assume_role_policy_name
  description = "Policy that allows assuming the CICDDeployRole in the Target account."
  policy      = data.aws_iam_policy_document.assume_target_role_policy_doc.json
  tags        = var.tags
}

# Optional: Attach this policy to the CI/CD user/role.
# For this task, creating the policy is sufficient. The test_assume_role.sh script
# will simulate having credentials for a principal that *has* this policy.
# If we wanted to attach it to a pre-existing user for a full TF demo:
# resource "aws_iam_user_policy_attachment" "cicd_user_assume_role_attachment" {
#   user       = var.cicd_principal_name # Assumes 'cicd_user' exists
#   policy_arn = aws_iam_policy.assume_target_role_policy.arn
# }
# Or for a role:
# resource "aws_iam_role_policy_attachment" "cicd_role_assume_role_attachment" {
#   role       = var.cicd_principal_name # Assumes 'cicd_role' exists
#   policy_arn = aws_iam_policy.assume_target_role_policy.arn
# }


output "assume_target_role_policy_arn" {
  description = "ARN of the created IAM policy in the CI/CD account."
  value       = aws_iam_policy.assume_target_role_policy.arn
}

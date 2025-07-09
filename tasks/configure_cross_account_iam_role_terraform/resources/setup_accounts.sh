#!/bin/bash
set -e

TARGET_INFRA_DIR="./resources/target_account_infra"
CICD_INFRA_DIR="./resources/cicd_account_infra"

echo "INFO: Starting setup for cross-account IAM roles..."

# Step 1: Apply Terraform for the Target Account
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Applying Terraform configuration for Target Account..."
echo "---------------------------------------------------------------------"
cd "$TARGET_INFRA_DIR"
echo "Current directory: $(pwd)"

# Simulate setting AWS context for Target Account (222222222222)
# In a real scenario, this would involve setting AWS_PROFILE or assuming a role.
# For this task, we rely on the provider block in target_account_infra/providers.tf
# and assume the environment is pre-configured for the "target" account when this runs.
echo "INFO: (Simulating AWS context for Target Account: 222222222222)"
export AWS_ACCOUNT_ID_FOR_TF="222222222222" # For any scripts that might use it.

terraform init -input=false -no-color
terraform apply -auto-approve -input=false -no-color

# Get the output of the deploy_role_arn from the Target account
TARGET_DEPLOY_ROLE_ARN=$(terraform output -raw deploy_role_arn)
if [ -z "$TARGET_DEPLOY_ROLE_ARN" ]; then
    echo "❌ ERROR: Could not retrieve 'deploy_role_arn' output from Target Account Terraform."
    cd ../.. # Back to task root
    exit 1
fi
echo "✅ Target Account setup complete. Deploy Role ARN: $TARGET_DEPLOY_ROLE_ARN"
cd ../.. # Back to task root


# Step 2: Apply Terraform for the CI/CD Account
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Applying Terraform configuration for CI/CD Account..."
echo "---------------------------------------------------------------------"
cd "$CICD_INFRA_DIR"
echo "Current directory: $(pwd)"

# Simulate setting AWS context for CI/CD Account (111111111111)
echo "INFO: (Simulating AWS context for CI/CD Account: 111111111111)"
export AWS_ACCOUNT_ID_FOR_TF="111111111111" # For any scripts that might use it.

terraform init -input=false -no-color
# Pass the obtained TARGET_DEPLOY_ROLE_ARN as a variable to this Terraform apply
terraform apply -auto-approve -input=false -no-color -var="target_deploy_role_arn=$TARGET_DEPLOY_ROLE_ARN"

ASSUME_POLICY_ARN=$(terraform output -raw assume_target_role_policy_arn)
if [ -z "$ASSUME_POLICY_ARN" ]; then
    echo "❌ ERROR: Could not retrieve 'assume_target_role_policy_arn' output from CI/CD Account Terraform."
    cd ../.. # Back to task root
    exit 1
fi
echo "✅ CI/CD Account setup complete. Assume Role Policy ARN: $ASSUME_POLICY_ARN"
cd ../.. # Back to task root

echo "---------------------------------------------------------------------"
echo "INFO: Cross-account IAM role and policy setup complete."
echo "  Target Account Deploy Role ARN: $TARGET_DEPLOY_ROLE_ARN"
echo "  CI/CD Account Assume Role Policy ARN: $ASSUME_POLICY_ARN"
echo "  These details are also available as outputs from their respective Terraform states."
echo "---------------------------------------------------------------------"

# Store ARNs for solution/verify scripts to use
cat << EOF > "$TARGET_INFRA_DIR/deploy_role_arn.txt"
TARGET_DEPLOY_ROLE_ARN=$TARGET_DEPLOY_ROLE_ARN
EOF
cat << EOF > "$CICD_INFRA_DIR/assume_policy_arn.txt"
ASSUME_POLICY_ARN=$ASSUME_POLICY_ARN
EOF

# Unset simulated account ID variable
unset AWS_ACCOUNT_ID_FOR_TF

exit 0

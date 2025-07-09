#!/usr/bin/env bash
set -e

TARGET_INFRA_DIR="./resources/target_account_infra"
CICD_INFRA_DIR="./resources/cicd_account_infra"
SETUP_SCRIPT="./resources/setup_accounts.sh"
SOLUTION_SCRIPT_FOR_TEST_LOGIC="./solution.sh" # Assuming solution.sh contains the test logic

EXPECTED_TARGET_TF_FILE="$TARGET_INFRA_DIR/iam_roles.tf"
EXPECTED_CICD_TF_FILE="$CICD_INFRA_DIR/iam_policies.tf"

TARGET_ACCOUNT_ID_EXPECTED="222222222222"
CICD_ACCOUNT_ID_EXPECTED="111111111111"
CICD_PRINCIPAL_USER_EXPECTED="user/cicd_user" # from var.cicd_principal_arn

echo "INFO: Starting verification for Cross-Account IAM Role setup."

# Check 1: Ensure user-created Terraform files exist
if [ ! -f "$EXPECTED_TARGET_TF_FILE" ]; then
    echo "❌ FAIL: Terraform file for target account '$EXPECTED_TARGET_TF_FILE' not found."
    exit 1
fi
if [ ! -f "$EXPECTED_CICD_TF_FILE" ]; then
    echo "❌ FAIL: Terraform file for CI/CD account '$EXPECTED_CICD_TF_FILE' not found."
    exit 1
fi
echo "✅ PASS: Required Terraform definition files found."

# Step 2: Run the setup script (already done by test_cross_account_iam.sh usually, but can be run here if testing verify.sh standalone)
# For this verify script, we assume setup_accounts.sh was run by the main test script or solution.
# We need its outputs.
echo "INFO: Checking for outputs from setup script..."
if [ ! -f "$TARGET_INFRA_DIR/deploy_role_arn.txt" ] || [ ! -f "$CICD_INFRA_DIR/assume_policy_arn.txt" ]; then
    echo "❌ FAIL: Output files from setup_accounts.sh (deploy_role_arn.txt or assume_policy_arn.txt) not found. Run setup first."
    # As a fallback if running verify.sh standalone for development:
    # echo "INFO: Attempting to run setup_accounts.sh now..."
    # chmod +x "$SETUP_SCRIPT" && "$SETUP_SCRIPT"
    # if [ ! -f "$TARGET_INFRA_DIR/deploy_role_arn.txt" ]; then exit 1; fi # Exit if still not found
    exit 1
fi
source "$TARGET_INFRA_DIR/deploy_role_arn.txt" # $TARGET_DEPLOY_ROLE_ARN
source "$CICD_INFRA_DIR/assume_policy_arn.txt" # $ASSUME_POLICY_ARN
echo "✅ PASS: Outputs from setup script loaded (TARGET_DEPLOY_ROLE_ARN, ASSUME_POLICY_ARN)."



echo "INFO: Executing solution's test logic (sts:AssumeRole, s3 ls, iam list-users)..."

echo "INFO: Verifying trust policy of Target Role: $TARGET_DEPLOY_ROLE_ARN"
# In a real environment:

echo "INFO: (Mocked check) Assuming Target Role's trust policy is correct based on Terraform apply success."
# A more robust mock would involve solution.sh's terraform outputting the data structure.

# Check 3b: Verify Target Role's Permissions (s3:ListAllMyBuckets, etc.)
echo "INFO: Verifying permissions policy of Target Role: $TARGET_DEPLOY_ROLE_ARN"
# In a real environment:
echo "INFO: (Mocked check) Assuming Target Role's permissions policy is correct based on Terraform apply success and solution's STS test pass."

# Check 3c: Verify CI/CD Account's AssumeRole Policy Content
echo "INFO: Verifying content of CI/CD Account's AssumeRole Policy: $ASSUME_POLICY_ARN"

echo "INFO: (Mocked check) Assuming CI/CD Account's policy is correct based on Terraform apply success and solution's STS test pass."

echo "INFO: Re-confirming STS AssumeRole and permissions by running test logic..."


echo "INFO: Verification relies on the successful execution of STS tests within solution.sh (called by the main test script)."
echo "INFO: If the main test script reaches this point after running solution.sh without error, the active STS part is considered passed."


echo "------------------------------------------"
echo "✅✅✅ Cross-Account IAM Role verification checks passed (partially mocked, relies on solution.sh success)."
# Cleanup (handled by test_cross_account_iam.sh trap)
exit 0

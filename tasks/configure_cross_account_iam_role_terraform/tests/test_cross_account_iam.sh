#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
RESOURCES_DIR="$TASK_ROOT_DIR/resources"
TARGET_INFRA_DIR="$RESOURCES_DIR/target_account_infra"
CICD_INFRA_DIR="$RESOURCES_DIR/cicd_account_infra"

SETUP_SCRIPT="$RESOURCES_DIR/setup_accounts.sh"
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Store original content of user-created files to restore them for clean reruns
TARGET_TF_FILE_PATH="$TARGET_INFRA_DIR/iam_roles.tf"
CICD_TF_FILE_PATH="$CICD_INFRA_DIR/iam_policies.tf"
TARGET_TF_ORIGINAL_CONTENT=""
CICD_TF_ORIGINAL_CONTENT=""

if [ -f "$TARGET_TF_FILE_PATH" ]; then
    TARGET_TF_ORIGINAL_CONTENT=$(cat "$TARGET_TF_FILE_PATH")
fi
if [ -f "$CICD_TF_FILE_PATH" ]; then
    CICD_TF_ORIGINAL_CONTENT=$(cat "$CICD_TF_FILE_PATH")
fi


cleanup_terraform_state_and_outputs() {
    echo "INFO: Cleaning up Terraform state and output files..."
    # Target account
    rm -f "$TARGET_INFRA_DIR/target_account.tfstate"
    rm -f "$TARGET_INFRA_DIR/target_account.tfstate.backup"
    rm -f "$TARGET_INFRA_DIR/.terraform.lock.hcl"
    rm -rf "$TARGET_INFRA_DIR/.terraform"
    rm -f "$TARGET_INFRA_DIR/deploy_role_arn.txt"

    # CI/CD account
    rm -f "$CICD_INFRA_DIR/cicd_account.tfstate"
    rm -f "$CICD_INFRA_DIR/cicd_account.tfstate.backup"
    rm -f "$CICD_INFRA_DIR/.terraform.lock.hcl"
    rm -rf "$CICD_INFRA_DIR/.terraform"
    rm -f "$CICD_INFRA_DIR/assume_policy_arn.txt"

    # Solution files
    rm -f "$TASK_ROOT_DIR/assumed_role_credentials.json"

    # Restore original user files if they existed
    if [ -n "$TARGET_TF_ORIGINAL_CONTENT" ]; then
        echo "$TARGET_TF_ORIGINAL_CONTENT" > "$TARGET_TF_FILE_PATH"
    else
        rm -f "$TARGET_TF_FILE_PATH" # if it was created by solution and didn't exist before
    fi
    if [ -n "$CICD_TF_ORIGINAL_CONTENT" ]; then
        echo "$CICD_TF_ORIGINAL_CONTENT" > "$CICD_TF_FILE_PATH"
    else
        rm -f "$CICD_TF_FILE_PATH"
    fi
}

# AWS resource cleanup function (mocked unless real credentials are used)
# This needs to be able to target both "accounts" if using profiles, or rely on LocalStack to distinguish.
cleanup_aws_iam_resources() {
    echo "INFO: Cleaning up AWS IAM resources (roles, policies)..."
    # This is complex because resources are in two "accounts" and depend on each other.
    # Destruction must be in reverse order of creation, and with correct "account" context.

    # Clean up CI/CD account resources (policy)
    echo "INFO: Attempting to destroy CI/CD account resources..."
    (cd "$CICD_INFRA_DIR" && \
     terraform init -input=false -no-color && \
     terraform destroy -auto-approve -input=false -no-color -var="target_deploy_role_arn=arn:aws:iam::222222222222:role/DummyRoleForDestroy" \
    ) || echo "WARN: Failed to destroy CI/CD account resources. This might be due to state issues or if they were already cleaned up."
    # Note: -var is used to satisfy variable requirement for destroy if ARN isn't available from a previous state.

    # Clean up Target account resources (role, policy, attachment)
    echo "INFO: Attempting to destroy Target account resources..."
    (cd "$TARGET_INFRA_DIR" && \
     terraform init -input=false -no-color && \
     terraform destroy -auto-approve -input=false -no-color \
    ) || echo "WARN: Failed to destroy Target account resources. This might be due to state issues or if they were already cleaned up."
}

full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_cross_account_iam.sh) ==="
    cleanup_aws_iam_resources # Cloud resources first
    cleanup_terraform_state_and_outputs # Then local state
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_cross_account_iam.sh) ==="
}
# Ensure cleanup always runs
trap full_cleanup EXIT


echo "INFO: Starting test for 'configure_cross_account_iam_role_terraform' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Ensure required Terraform files are initially *not* present or are placeholders,
# as the task implies the user creates them.
# For this test, we assume solution.sh might check for them or use pre-provided ones.
# The solution.sh I wrote assumes they are created by the user.
# To make this test runnable, it should first call a script that places the solution's TF files.
# Or, this test script itself can copy the solution TF files into place.

# For now, assume the user (or a previous step) is responsible for creating:
# - resources/target_account_infra/iam_roles.tf
# - resources/cicd_account_infra/iam_policies.tf
# The solution.sh checks for these. If they are missing, solution.sh will fail, which is a valid test outcome.
# The provided TF files in the directory structure are the "solution" files.

# Make scripts executable
chmod +x "$SETUP_SCRIPT"
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the solution script.
# The solution script itself calls setup_script and then performs STS tests.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script..."
echo "---------------------------------------------------------------------"
# The solution script is expected to:
# 1. Call setup_script (which applies TF in both "accounts")
# 2. Perform STS assume-role tests.
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script (including setup and STS tests) executed successfully."


# Step 2: Run the verification script
# This script performs additional checks on the state of resources.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully."


echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'configure_cross_account_iam_role_terraform' task test completed successfully."
echo "---------------------------------------------------------------------"

# Disable trap for successful exit to let it run once.
exit 0

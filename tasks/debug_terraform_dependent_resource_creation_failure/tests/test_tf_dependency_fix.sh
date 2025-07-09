#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
INFRA_DIR="$TASK_ROOT_DIR/resources/infra"
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"
ORIGINAL_MAIN_TF_PATH="$INFRA_DIR/main.tf" # The file solution.sh will modify

# Store original content of main.tf to restore for clean reruns or if test fails.
# This assumes the `main.tf` in `resources/infra` is the *broken* version initially.
if [ ! -f "$ORIGINAL_MAIN_TF_PATH" ]; then
    echo "ERROR: Original (broken) main.tf not found at $ORIGINAL_MAIN_TF_PATH. Test setup incorrect."
    exit 1
fi
ORIGINAL_MAIN_TF_CONTENT=$(cat "$ORIGINAL_MAIN_TF_PATH")

# Cleanup function
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_tf_dependency_fix.sh) ==="
    # Restore original main.tf
    echo "INFO: Restoring original main.tf..."
    echo "$ORIGINAL_MAIN_TF_CONTENT" > "$ORIGINAL_MAIN_TF_PATH"

    # verify.sh should handle its own terraform state/lock file cleanup via its trap.
    # If verify.sh failed, its trap might have already run.
    # We can add a redundant cleanup here if needed, but it's better if verify.sh's trap is robust.
    # Example: (cd "$INFRA_DIR" && rm -f .terraform.lock.hcl debug_dependencies.tfstate* && rm -rf .terraform) || true
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_tf_dependency_fix.sh) ==="
}
# Ensure cleanup always runs
trap full_cleanup EXIT


echo "INFO: Starting test for 'debug_terraform_dependent_resource_creation_failure' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: (Optional) Attempt to apply the original/broken main.tf to show it fails.
# This is good for demonstrating the problem but might be slow or require specific failure conditions.
# For CI, we might skip this and go straight to solution.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 0 (Optional) - Verifying the original main.tf is indeed problematic (not run in this test)..."
# (cd "$INFRA_DIR" && terraform init -input=false -no-color && terraform apply -auto-approve -input=false -no-color)
# This command above would likely fail, which is the point of the task.
# For this automated test, we assume it's broken and proceed to the solution.
echo "INFO: Assuming original main.tf is problematic as per task design."
echo "---------------------------------------------------------------------"


# Step 2: Run the solution script
# This script modifies INFRA_DIR/main.tf with the corrected version.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script (to fix main.tf)..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script executed successfully (main.tf should now be fixed)."

# Verify that main.tf was actually changed by the solution script
MODIFIED_MAIN_TF_CONTENT=$(cat "$ORIGINAL_MAIN_TF_PATH")
if [ "$MODIFIED_MAIN_TF_CONTENT" == "$ORIGINAL_MAIN_TF_CONTENT" ]; then
    echo "❌ TEST FAIL: Solution script did not modify '$ORIGINAL_MAIN_TF_PATH'."
    exit 1
fi
if ! grep -q "depends_on = \[aws_internet_gateway_attachment.gw_attachment\]" "$ORIGINAL_MAIN_TF_PATH"; then
    echo "❌ TEST FAIL: Expected fix (depends_on gw_attachment) not found in modified main.tf."
    exit 1
fi
echo "✅ main.tf appears to have been modified by the solution with expected fixes."


# Step 3: Run the verification script
# This script will cd into INFRA_DIR and run init, validate, apply, destroy.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script on the fixed main.tf..."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed for the fixed main.tf."
    # verify.sh should have its own trap for cleaning up its TF files.
    # The main trap here will restore the original main.tf.
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully and confirmed the fix."


# Note: The main cleanup (restoring original main.tf) is handled by the trap.
# verify.sh's trap handles its own .terraform state and lock files.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'debug_terraform_dependent_resource_creation_failure' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

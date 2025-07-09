#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
RESOURCES_DIR="$TASK_ROOT_DIR/resources"
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Ensure helper scripts are executable
chmod +x "$RESOURCES_DIR/setup_initial_infra.sh"
chmod +x "$RESOURCES_DIR/simulate_drift.sh"
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"

echo "INFO: Starting test for 'diagnose_and_fix_terraform_drift' task..."

# Clean up previous Terraform state and outputs in resources directory
echo "INFO: Cleaning up previous Terraform state and outputs from $RESOURCES_DIR..."
rm -f "$RESOURCES_DIR/terraform.tfstate"
rm -f "$RESOURCES_DIR/terraform.tfstate.backup"
rm -f "$RESOURCES_DIR/terraform_outputs.json"
rm -f "$RESOURCES_DIR/.terraform.lock.hcl"
rm -rf "$RESOURCES_DIR/.terraform"
# Clean up solution-generated files
rm -f "$RESOURCES_DIR/plan_output.txt"
rm -f "$RESOURCES_DIR/remediation_plan.txt"
rm -f "$RESOURCES_DIR/verify_plan_output.txt"


# Step 1: Setup initial infrastructure
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Setting up initial AWS infrastructure..."
echo "---------------------------------------------------------------------"
# Run setup_initial_infra.sh from the task's root directory. The script itself cds into resources.
if ! "$RESOURCES_DIR/setup_initial_infra.sh"; then
    echo "❌ TEST FAIL: Initial infrastructure setup failed."
    exit 1
fi
echo "✅ Initial infrastructure setup complete."

# Step 2: Simulate drift
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Simulating drift on AWS resources..."
echo "---------------------------------------------------------------------"
# Run simulate_drift.sh from the task's root directory. The script itself cds into resources.
if ! "$RESOURCES_DIR/simulate_drift.sh"; then
    echo "❌ TEST FAIL: Drift simulation failed."
    # Attempt to destroy resources if drift simulation failed mid-way, to clean up.
    echo "INFO: Attempting to destroy potentially modified resources..."
    (cd "$RESOURCES_DIR" && terraform destroy -auto-approve -input=false) || echo "WARN: Failed to destroy resources during cleanup."
    exit 1
fi
echo "✅ Drift simulation complete."

# Step 3: Run the solution script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 3 - Running solution script to remediate drift..."
echo "---------------------------------------------------------------------"
# The solution script is expected to be run from the task root.
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed."
    # Attempt to destroy resources if solution failed, to clean up.
    echo "INFO: Attempting to destroy potentially modified resources..."
    (cd "$RESOURCES_DIR" && terraform destroy -auto-approve -input=false) || echo "WARN: Failed to destroy resources during cleanup."
    exit 1
fi
echo "✅ Solution script executed successfully."

# Step 4: Run the verification script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 4 - Running verification script..."
echo "---------------------------------------------------------------------"
# The verify script is expected to be run from the task root.
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Attempt to destroy resources if verification failed, to clean up.
    echo "INFO: Attempting to destroy potentially modified resources..."
    (cd "$RESOURCES_DIR" && terraform destroy -auto-approve -input=false) || echo "WARN: Failed to destroy resources during cleanup."
    exit 1
fi
echo "✅ Verification script executed successfully and confirmed remediation."

# Step 5: Cleanup - Destroy all resources
echo "---------------------------------------------------------------------"
echo "INFO: STEP 5 - Cleaning up: Destroying AWS resources..."
echo "---------------------------------------------------------------------"
(cd "$RESOURCES_DIR" && terraform destroy -auto-approve -input=false)
echo "✅ Resources destroyed."

# Final cleanup of local files
echo "INFO: Final cleanup of local Terraform files..."
rm -f "$RESOURCES_DIR/terraform.tfstate"
rm -f "$RESOURCES_DIR/terraform.tfstate.backup"
rm -f "$RESOURCES_DIR/terraform_outputs.json"
rm -f "$RESOURCES_DIR/.terraform.lock.hcl"
rm -rf "$RESOURCES_DIR/.terraform"
rm -f "$RESOURCES_DIR/plan_output.txt" # From solution
rm -f "$RESOURCES_DIR/remediation_plan.txt" # From solution
rm -f "$RESOURCES_DIR/verify_plan_output.txt" # From verify

echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'diagnose_and_fix_terraform_drift' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

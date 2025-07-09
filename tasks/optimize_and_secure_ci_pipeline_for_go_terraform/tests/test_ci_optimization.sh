#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Path to the original workflow, which solution.sh uses as a base
ORIGINAL_WORKFLOW_PATH="$TASK_ROOT_DIR/resources/.github/workflows/ci.original.yml"
# Path where the solution script will create the enhanced workflow
ENHANCED_WORKFLOW_DIR_RELATIVE_TO_TASK_ROOT=".github/workflows" # As per solution.sh logic
ENHANCED_WORKFLOW_FILE_PATH="$TASK_ROOT_DIR/$ENHANCED_WORKFLOW_DIR_RELATIVE_TO_TASK_ROOT/ci.enhanced.yml"


# Cleanup function
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_ci_optimization.sh) ==="
    # Delete the .github directory created by the solution in the task's root
    if [ -d "$TASK_ROOT_DIR/$ENHANCED_WORKFLOW_DIR_RELATIVE_TO_TASK_ROOT" ]; then
        echo "INFO: Removing created $ENHANCED_WORKFLOW_DIR_RELATIVE_TO_TASK_ROOT directory..."
        rm -rf "$TASK_ROOT_DIR/$ENHANCED_WORKFLOW_DIR_RELATIVE_TO_TASK_ROOT"
    fi
    # Remove any local scan results if verify.sh created them and failed to clean up
    rm -f "$TASK_ROOT_DIR/resources/go_app/verify-gosec.json"
    rm -f "$TASK_ROOT_DIR/resources/terraform_infra/verify-tfsec.json"
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_ci_optimization.sh) ==="
}
# Ensure cleanup always runs
trap full_cleanup EXIT


echo "INFO: Starting test for 'optimize_and_secure_ci_pipeline_for_go_terraform' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Ensure the original workflow file exists for the solution script to copy/use
if [ ! -f "$ORIGINAL_WORKFLOW_PATH" ]; then
    echo "ERROR: Original workflow file '$ORIGINAL_WORKFLOW_PATH' not found. Test setup is incomplete."
    exit 1
fi

# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the solution script
# This script creates/modifies .github/workflows/ci.enhanced.yml
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script (to create ci.enhanced.yml)..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script executed successfully."

# Check if solution created the enhanced workflow file
if [ ! -f "$ENHANCED_WORKFLOW_FILE_PATH" ]; then
    echo "❌ TEST FAIL: Solution did not create '$ENHANCED_WORKFLOW_FILE_PATH'."
    exit 1
fi
echo "✅ Enhanced workflow file '$ENHANCED_WORKFLOW_FILE_PATH' found."


# Step 2: Run the verification script
# This script performs static analysis of ci.enhanced.yml and optionally local tool runs.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully and confirmed CI/CD enhancements."


# Note: The main cleanup (removing .github dir) is handled by the trap.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'optimize_and_secure_ci_pipeline_for_go_terraform' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

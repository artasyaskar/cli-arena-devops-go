#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)

SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"
BROKEN_DOCKERFILE_PATH="$TASK_ROOT_DIR/resources/Dockerfile.broken"
FIXED_DOCKERFILE_EXPECTED_PATH="$TASK_ROOT_DIR/Dockerfile.fixed"

echo "INFO: Starting test for 'troubleshoot_multi_stage_docker_build_failure' task..."
echo "Current directory: $(pwd)"

# Ensure we are in the task's root directory
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the 'troubleshoot_multi_stage_docker_build_failure' task directory."
    exit 1
fi

# Clean up artifacts from previous runs
echo "INFO: Cleaning up artifacts from previous test runs..."
rm -f "$FIXED_DOCKERFILE_EXPECTED_PATH"
# Clean up any lingering docker items from verify.sh if it failed previously
docker rm -f fixed-app-container-test >/dev/null 2>&1 || true
docker rmi fixed-app-test:latest >/dev/null 2>&1 || true


# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the solution script (which should generate Dockerfile.fixed)
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script (to generate Dockerfile.fixed)..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1
fi
echo "✅ Solution script executed successfully."

# Check if solution created Dockerfile.fixed
if [ ! -f "$FIXED_DOCKERFILE_EXPECTED_PATH" ]; then
    echo "❌ TEST FAIL: Solution did not create '$FIXED_DOCKERFILE_EXPECTED_PATH'."
    exit 1
fi
echo "✅ Solution script created '$FIXED_DOCKERFILE_EXPECTED_PATH'."


# Step 2: Run the verification script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
# The verify script handles building Dockerfile.fixed, running container, and all checks.
# It also handles its own Docker cleanup (container, image) via a trap.
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Verify script's trap should handle Docker cleanup.
    exit 1
fi
echo "✅ Verification script executed successfully and confirmed Dockerfile.fixed is correct."


# Step 3: Final cleanup of files created by solution/test
echo "---------------------------------------------------------------------"
echo "INFO: STEP 3 - Final cleanup of local files..."
echo "---------------------------------------------------------------------"
rm -f "$FIXED_DOCKERFILE_EXPECTED_PATH"
echo "✅ Local file cleanup complete."

echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'troubleshoot_multi_stage_docker_build_failure' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

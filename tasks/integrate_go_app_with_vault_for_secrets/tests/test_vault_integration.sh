#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Paths to files that solution.sh modifies, to restore them for clean reruns
APP_MAIN_GO_PATH="$TASK_ROOT_DIR/resources/app/main.go"
APP_GO_MOD_PATH="$TASK_ROOT_DIR/resources/app/go.mod"
DOCKER_COMPOSE_YAML_PATH="$TASK_ROOT_DIR/resources/docker-compose.yml"

# Store original content
APP_MAIN_GO_ORIGINAL_CONTENT=$(cat "$APP_MAIN_GO_PATH")
APP_GO_MOD_ORIGINAL_CONTENT=$(cat "$APP_GO_MOD_PATH")
DOCKER_COMPOSE_YAML_ORIGINAL_CONTENT=$(cat "$DOCKER_COMPOSE_YAML_PATH")


cleanup_modified_files() {
    echo "INFO: Restoring original resource files..."
    echo "$APP_MAIN_GO_ORIGINAL_CONTENT" > "$APP_MAIN_GO_PATH"
    echo "$APP_GO_MOD_ORIGINAL_CONTENT" > "$APP_GO_MOD_PATH"
    echo "$DOCKER_COMPOSE_YAML_ORIGINAL_CONTENT" > "$DOCKER_COMPOSE_YAML_PATH"
    rm -f "$TASK_ROOT_DIR/setup_vault_secrets.sh" # Remove script created by solution
}

# Full cleanup routine including Docker
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_vault_integration.sh) ==="
    # verify.sh should call `docker-compose down`, but as a safeguard:
    if [ -f "$DOCKER_COMPOSE_YAML_PATH" ]; then # Check if compose file exists
      (cd "$TASK_ROOT_DIR/resources" && docker-compose -f docker-compose.yml down --remove-orphans --volumes >/dev/null 2>&1) || true
    fi
    cleanup_modified_files
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_vault_integration.sh) ==="
}
# Ensure cleanup always runs
trap full_cleanup EXIT


echo "INFO: Starting test for 'integrate_go_app_with_vault_for_secrets' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"
# setup_vault_secrets.sh is created by solution.sh, which will also chmod it.


# Step 1: Run the solution script
# This script modifies main.go, go.mod, docker-compose.yml, and creates setup_vault_secrets.sh
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script executed successfully (modified files and created helper script)."


# Step 2: Run the verification script
# This script handles docker-compose up, running vault setup, and checking app behavior.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Verify script should attempt its own docker cleanup on failure if possible.
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully and confirmed Vault integration."


# Note: The main cleanup (Docker down, restoring files) is handled by the trap.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'integrate_go_app_with_vault_for_secrets' task test completed successfully."
echo "---------------------------------------------------------------------"

# Disable trap for successful exit if you want to inspect the state.
# For CI, letting trap run for cleanup is best.
exit 0

#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Paths to files that solution.sh modifies, to restore them for clean reruns
APP_MAIN_GO_PATH="$TASK_ROOT_DIR/resources/app/main.go"
APP_GO_MOD_PATH="$TASK_ROOT_DIR/resources/app/go.mod" # Solution doesn't change this for encoding/json
APP_DOCKERFILE_PATH="$TASK_ROOT_DIR/resources/app/Dockerfile" # Solution might tweak this
FLUENT_CONF_PATH="$TASK_ROOT_DIR/resources/fluentd/fluent.conf"
DOCKER_COMPOSE_YAML_PATH="$TASK_ROOT_DIR/resources/docker-compose.yml"
FLUENTD_LOG_DIR_HOST_PATH="$TASK_ROOT_DIR/resources/fluentd_logs"


# Store original content
APP_MAIN_GO_ORIGINAL_CONTENT=$(cat "$APP_MAIN_GO_PATH")
APP_GO_MOD_ORIGINAL_CONTENT=$(cat "$APP_GO_MOD_PATH")
APP_DOCKERFILE_ORIGINAL_CONTENT=$(cat "$APP_DOCKERFILE_PATH")
FLUENT_CONF_ORIGINAL_CONTENT=$(cat "$FLUENT_CONF_PATH") # Might be empty placeholder initially
DOCKER_COMPOSE_YAML_ORIGINAL_CONTENT=$(cat "$DOCKER_COMPOSE_YAML_PATH")


cleanup_modified_files() {
    echo "INFO: Restoring original resource files..."
    echo "$APP_MAIN_GO_ORIGINAL_CONTENT" > "$APP_MAIN_GO_PATH"
    echo "$APP_GO_MOD_ORIGINAL_CONTENT" > "$APP_GO_MOD_PATH"
    echo "$APP_DOCKERFILE_ORIGINAL_CONTENT" > "$APP_DOCKERFILE_PATH"
    echo "$FLUENT_CONF_ORIGINAL_CONTENT" > "$FLUENT_CONF_PATH"
    echo "$DOCKER_COMPOSE_YAML_ORIGINAL_CONTENT" > "$DOCKER_COMPOSE_YAML_PATH"
    # Remove host log directory content, not the directory itself if it was pre-created
    rm -rf "$FLUENTD_LOG_DIR_HOST_PATH"/*
}

# Full cleanup routine including Docker
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_centralized_logging.sh) ==="
    # verify.sh should call `docker-compose down`, but as a safeguard:
    if [ -f "$DOCKER_COMPOSE_YAML_PATH" ]; then # Check if compose file exists (it's modified by solution)
      (cd "$TASK_ROOT_DIR/resources" && docker-compose -f docker-compose.yml down -v --remove-orphans >/dev/null 2>&1) || true
    fi
    cleanup_modified_files
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_centralized_logging.sh) ==="
}
# Ensure cleanup always runs
trap full_cleanup EXIT


echo "INFO: Starting test for 'setup_centralized_logging_docker_go_fluentd' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Create host log directory for Fluentd if it doesn't exist, with open permissions for the test
mkdir -p "$FLUENTD_LOG_DIR_HOST_PATH"
chmod 777 "$FLUENTD_LOG_DIR_HOST_PATH"


# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the solution script
# This script modifies main.go, fluent.conf, docker-compose.yml.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script executed successfully (modified files and configurations)."


# Step 2: Run the verification script
# This script handles docker-compose up, sending test requests, and checking logs.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Verify script should attempt its own docker cleanup on failure if possible.
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully and confirmed centralized logging setup."


# Note: The main cleanup (Docker down, restoring files) is handled by the trap.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'setup_centralized_logging_docker_go_fluentd' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

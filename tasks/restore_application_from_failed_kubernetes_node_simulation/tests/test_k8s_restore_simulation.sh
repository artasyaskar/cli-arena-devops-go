#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"
SETUP_SCRIPT_RESOURCE_PATH="$TASK_ROOT_DIR/resources/setup_app_and_backup.sh"

# Paths to files that solution.sh might create or that verify.sh depends on being cleaned up
RESTORED_COMPOSE_FILE_PATH="$TASK_ROOT_DIR/docker-compose.restored.yml"
BACKUP_DIR_RESOURCE_PATH="$TASK_ROOT_DIR/resources/backups"

# Docker related names (must match those used in scripts and compose files)
APP_VOLUME_NAME="app_data_explicit_volume"
SETUP_COMPOSE_FILE_RESOURCE_PATH="$TASK_ROOT_DIR/resources/docker-compose.setup.yml"


# Full cleanup routine
# This is critical because this task involves Docker volumes and running containers.
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING (test_k8s_restore_simulation.sh) ==="

    echo "INFO: (Test Script) Stopping and removing containers from restored compose file (if exists)..."
    if [ -f "$RESTORED_COMPOSE_FILE_PATH" ]; then
        docker-compose -f "$RESTORED_COMPOSE_FILE_PATH" down -v --remove-orphans > /dev/null 2>&1 || true
    fi

    echo "INFO: (Test Script) Stopping and removing containers from setup compose file (if exists)..."
    if [ -f "$SETUP_COMPOSE_FILE_RESOURCE_PATH" ]; then
        docker-compose -f "$SETUP_COMPOSE_FILE_RESOURCE_PATH" down -v --remove-orphans > /dev/null 2>&1 || true
    fi
    
    echo "INFO: (Test Script) Removing Docker volume '$APP_VOLUME_NAME' (if exists)..."
    docker volume rm "$APP_VOLUME_NAME" > /dev/null 2>&1 || true

    echo "INFO: (Test Script) Cleaning up backup directory '$BACKUP_DIR_RESOURCE_PATH'..."
    # Create backup dir if it was removed by mistake, then clear its contents
    mkdir -p "$BACKUP_DIR_RESOURCE_PATH" # Ensure it exists for rm command
    rm -rf "${BACKUP_DIR_RESOURCE_PATH}"/* 

    echo "INFO: (Test Script) Removing restored compose file (if exists)..."
    rm -f "$RESTORED_COMPOSE_FILE_PATH"
    
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED (test_k8s_restore_simulation.sh) ==="
}
# Ensure cleanup always runs. Placed at the start to define it early.
trap full_cleanup EXIT


echo "INFO: Starting test for 'restore_application_from_failed_kubernetes_node_simulation' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the task directory."
    exit 1
fi

# Ensure the backup directory exists before setup script runs (setup script also does this)
mkdir -p "$BACKUP_DIR_RESOURCE_PATH"

# Make scripts executable
chmod +x "$SETUP_SCRIPT_RESOURCE_PATH" # This is a resource, but test script calls it via verify
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the verification script
# The verify script is comprehensive: it runs setup, simulates failure, runs solution, and checks.
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running verification script..."
echo "INFO: This will include: initial setup, data population, backup, failure simulation, solution execution, and final checks."
echo "---------------------------------------------------------------------"
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Trap will handle cleanup.
    exit 1
fi
echo "✅ Verification script executed successfully and confirmed all stages of restore process."


# Note: The main cleanup is handled by the trap.
# verify.sh also has its own trap, which should run first upon its exit.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'restore_application_from_failed_kubernetes_node_simulation' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

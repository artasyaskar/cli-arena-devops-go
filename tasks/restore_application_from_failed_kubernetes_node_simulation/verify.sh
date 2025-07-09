#!/bin/bash
set -e

SETUP_SCRIPT="./resources/setup_app_and_backup.sh"
SOLUTION_SCRIPT_TO_TEST="./solution.sh" # The user's solution script
APP_SERVICE_NAME="app_service"
APP_CONTAINER_NAME="stateful_go_app_container"
APP_VOLUME_NAME="app_data_explicit_volume" # Explicitly named volume
RESTORED_COMPOSE_FILE="./docker-compose.restored.yml" # Expected to be created by solution
SETUP_COMPOSE_FILE="./resources/docker-compose.setup.yml" # Used by setup script
BACKUP_DIR="./resources/backups"
APP_URL="http://localhost:8080"

INITIAL_KEY1="initial_fruit"
INITIAL_VALUE1="banana"
INITIAL_KEY2="initial_color"
INITIAL_VALUE2="yellow"

POST_RESTORE_KEY="new_planet"
POST_RESTORE_VALUE="mars"


cleanup_all() {
  echo "INFO: (Verify) Full cleanup running..."
  echo "INFO: (Verify) Stopping and removing containers from restored compose file (if exists)..."
  if [ -f "$RESTORED_COMPOSE_FILE" ]; then
    docker-compose -f "$RESTORED_COMPOSE_FILE" down -v --remove-orphans > /dev/null 2>&1 || true
  fi
  echo "INFO: (Verify) Stopping and removing containers from setup compose file (if exists)..."
  if [ -f "$SETUP_COMPOSE_FILE" ]; then
    docker-compose -f "$SETUP_COMPOSE_FILE" down -v --remove-orphans > /dev/null 2>&1 || true
  fi

  echo "INFO: (Verify) Removing Docker volume '$APP_VOLUME_NAME' (if exists)..."
  docker volume rm "$APP_VOLUME_NAME" > /dev/null 2>&1 || true

  echo "INFO: (Verify) Cleaning up backup directory '$BACKUP_DIR'..."
  rm -rf "${BACKUP_DIR}"/* # Clear content, not dir itself
  
  echo "INFO: (Verify) Removing restored compose file..."
  rm -f "$RESTORED_COMPOSE_FILE"
  echo "INFO: (Verify) Cleanup complete."
}
trap cleanup_all EXIT

# --- Main Verification Steps ---
echo "INFO: === Starting Verification for Stateful App Restore Task ==="

# Step 1: Run setup script to initialize app, add data, and create a backup
echo "INFO: --- Step 1: Running setup script ($SETUP_SCRIPT) ---"
chmod +x "$SETUP_SCRIPT"
if ! "$SETUP_SCRIPT"; then
    echo "❌ FAIL: Setup script '$SETUP_SCRIPT' failed."
    exit 1
fi
# setup_script adds 'fruit=apple', 'color=red', 'city=testville'. Let's use these for initial check.
echo "✅ Setup script completed. App running with initial data, backup taken."

# Step 2: Verify initial data in the running app (before failure)
echo "INFO: --- Step 2: Verifying initial data in app (pre-failure) ---"
if ! curl -s "$APP_URL/get?key=fruit" | grep -q "apple"; then
    echo "❌ FAIL: Initial data 'fruit=apple' not found pre-failure."
    exit 1
fi
if ! curl -s "$APP_URL/get?key=city" | grep -q "testville"; then
    echo "❌ FAIL: Initial data 'city=testville' not found pre-failure."
    exit 1
fi
echo "✅ Initial data verified in app (pre-failure)."

# Step 3: Simulate Failure
echo "INFO: --- Step 3: Simulating failure (stopping app, removing volume) ---"
echo "INFO: Stopping app container '$APP_CONTAINER_NAME'..."
docker-compose -f "$SETUP_COMPOSE_FILE" stop "$APP_SERVICE_NAME" # Stop service
docker-compose -f "$SETUP_COMPOSE_FILE" rm -f "$APP_SERVICE_NAME" # Remove container
echo "INFO: Removing/corrupting Docker volume '$APP_VOLUME_NAME'..."
if ! docker volume rm "$APP_VOLUME_NAME"; then
    echo "❌ WARN: Failed to remove volume '$APP_VOLUME_NAME'. It might not exist or be in use. Test might be invalid if data persists."
    # This could be a failure if volume must be removed for test.
    # For now, a warning, solution should handle volume re-creation or cleaning.
fi
# Ensure volume is gone or app will just restart with old data if solution doesn't handle it.
if docker volume inspect "$APP_VOLUME_NAME" > /dev/null 2>&1; then
    echo "❌ FAIL: Docker volume '$APP_VOLUME_NAME' still exists after attempting removal. Cannot reliably test restore."
    exit 1
fi
echo "✅ Failure simulated: App container stopped, volume removed."


# Step 4: Run the user's solution script
echo "INFO: --- Step 4: Running solution script ($SOLUTION_SCRIPT_TO_TEST) ---"
chmod +x "$SOLUTION_SCRIPT_TO_TEST"
if ! "$SOLUTION_SCRIPT_TO_TEST"; then
    echo "❌ FAIL: Solution script '$SOLUTION_SCRIPT_TO_TEST' failed."
    exit 1
fi
echo "✅ Solution script completed."

# Check if restored compose file was created
if [ ! -f "$RESTORED_COMPOSE_FILE" ]; then
    echo "❌ FAIL: Solution did not create the expected restored compose file '$RESTORED_COMPOSE_FILE'."
    exit 1
fi
echo "✅ Restored compose file '$RESTORED_COMPOSE_FILE' found."


# Step 5: Verify application state after restoration
echo "INFO: --- Step 5: Verifying application state post-restoration ---"
# Check if app is running (solution should have started it via docker-compose.restored.yml)
if ! docker ps -f name="^/${APP_CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "$APP_CONTAINER_NAME"; then
    echo "❌ FAIL: Application container '$APP_CONTAINER_NAME' is not running after solution script execution."
    docker-compose -f "$RESTORED_COMPOSE_FILE" logs "$APP_SERVICE_NAME" # Show logs from restored app
    exit 1
fi
echo "✅ Application container is running post-restoration."

# Check if app is responsive
if ! curl -s "$APP_URL/" > /dev/null; then
    echo "❌ FAIL: Restored application is not responding on $APP_URL."
    docker-compose -f "$RESTORED_COMPOSE_FILE" logs "$APP_SERVICE_NAME"
    exit 1
fi
echo "✅ Restored application is responsive."

# Verify restored data (data that was present at backup time)
echo "INFO: Verifying restored data..."
if ! curl -s "$APP_URL/get?key=fruit" | grep -q "apple"; then
    echo "❌ FAIL: Restored data 'fruit=apple' not found post-restoration."
    exit 1
fi
if ! curl -s "$APP_URL/get?key=city" | grep -q "testville"; then
    echo "❌ FAIL: Restored data 'city=testville' not found post-restoration."
    exit 1
fi
echo "✅ Restored data verified successfully via app API."

# Step 6: Verify ability to write and read new data post-restoration
echo "INFO: --- Step 6: Verifying write/read of new data post-restoration ---"
echo "INFO: Writing new data: $POST_RESTORE_KEY = $POST_RESTORE_VALUE"
curl -s -X POST "$APP_URL/set?key=$POST_RESTORE_KEY&value=$POST_RESTORE_VALUE"
echo # newline

# Verify new data can be read back
if ! curl -s "$APP_URL/get?key=$POST_RESTORE_KEY" | grep -q "$POST_RESTORE_VALUE"; then
    echo "❌ FAIL: Failed to read newly written data ('$POST_RESTORE_KEY' = '$POST_RESTORE_VALUE') post-restoration."
    exit 1
fi
echo "✅ New data written and read successfully post-restoration."

# Step 7: (Harder check) Verify persistence of new data by inspecting volume again (or restarting app)
# For this, we'll stop and start the app using the *restored* compose file, then check all data.
echo "INFO: --- Step 7: Verifying persistence of new data after app restart ---"
echo "INFO: Stopping restored app..."
docker-compose -f "$RESTORED_COMPOSE_FILE" stop "$APP_SERVICE_NAME"
echo "INFO: Starting restored app again..."
docker-compose -f "$RESTORED_COMPOSE_FILE" up -d "$APP_SERVICE_NAME" # Don't use --build here
echo "INFO: Waiting for app to restart (10 seconds)..."
sleep 10

if ! curl -s "$APP_URL/" > /dev/null; then
    echo "❌ FAIL: Application did not restart correctly or is not responding after testing persistence."
    docker-compose -f "$RESTORED_COMPOSE_FILE" logs "$APP_SERVICE_NAME"
    exit 1
fi
echo "✅ Application restarted successfully for persistence check."

echo "INFO: Verifying all data (original restored + new) after restart..."
# Original restored data
if ! curl -s "$APP_URL/get?key=fruit" | grep -q "apple"; then
    echo "❌ FAIL: Original restored data 'fruit=apple' NOT found after app restart for persistence check."
    exit 1
fi
# New data
if ! curl -s "$APP_URL/get?key=$POST_RESTORE_KEY" | grep -q "$POST_RESTORE_VALUE"; then
    echo "❌ FAIL: New data '$POST_RESTORE_KEY=$POST_RESTORE_VALUE' NOT found after app restart for persistence check."
    exit 1
fi
echo "✅ All data (original restored + new) verified after app restart. Persistence confirmed."


echo "---------------------------------------------------------------------"
echo "✅✅✅ All Kubernetes Node Failure Simulation and Restore verification tests passed."
# Trap will handle final cleanup
exit 0

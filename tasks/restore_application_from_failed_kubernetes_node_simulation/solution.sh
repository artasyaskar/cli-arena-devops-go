#!/bin/bash
set -e

APP_SERVICE_NAME="app_service" # As in docker-compose files
APP_CONTAINER_NAME="stateful_go_app_container" # As in docker-compose files
APP_VOLUME_NAME="app_data_explicit_volume" # Explicitly named volume
BACKUP_DIR="./resources/backups"
RESTORED_COMPOSE_FILE="docker-compose.restored.yml" # To be created by this script
SETUP_COMPOSE_FILE="./resources/docker-compose.setup.yml" # Reference for creating restored compose

echo "INFO: Starting application restoration process..."

# Step 1: Detect if app_service is down
echo "INFO: Checking status of application service '$APP_SERVICE_NAME'..."
# `docker-compose ps -q $APP_SERVICE_NAME` returns an ID if running, empty otherwise.
# Or check `docker ps` for the container name.
if docker ps -f name="^/${APP_CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "$APP_CONTAINER_NAME"; then
    echo "WARN: Application container '$APP_CONTAINER_NAME' is still running. For a realistic restore test, it should be stopped and its volume potentially corrupted/removed first."
    echo "INFO: Proceeding with restore logic assuming this is part of a larger test that handled failure simulation."
    # Optionally, stop it here if it's found running:
    # echo "INFO: Stopping running container '$APP_CONTAINER_NAME'..."
    # docker stop "$APP_CONTAINER_NAME" || true
    # docker rm "$APP_CONTAINER_NAME" || true
else
    echo "✅ Application container '$APP_CONTAINER_NAME' is not running (as expected for a failure scenario)."
fi

# Step 2: Identify the latest valid backup
echo "INFO: Identifying latest valid backup from '$BACKUP_DIR'..."
# Valid: non-empty .tar.gz file. Latest: by filename timestamp.
LATEST_BACKUP=$(ls -1 "$BACKUP_DIR"/app_data_backup_*.tar.gz 2>/dev/null | sort -r | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ ERROR: No backup files found in '$BACKUP_DIR'."
    exit 1
fi
if [ ! -s "$LATEST_BACKUP" ]; then
    echo "❌ ERROR: Latest backup file '$LATEST_BACKUP' is empty or invalid."
    exit 1
fi
# Basic tar validation (check if it's a readable tar archive)
if ! tar -tzf "$LATEST_BACKUP" > /dev/null 2>&1; then
    echo "❌ ERROR: Latest backup file '$LATEST_BACKUP' is not a valid tar.gz archive."
    exit 1
fi
echo "✅ Using latest valid backup: $LATEST_BACKUP"

# Step 3: Prepare Docker volume for restoration
echo "INFO: Preparing Docker volume '$APP_VOLUME_NAME' for restoration..."
# Check if volume exists
if docker volume inspect "$APP_VOLUME_NAME" > /dev/null 2>&1; then
    echo "INFO: Volume '$APP_VOLUME_NAME' exists. Removing it to simulate clean restore..."
    # In a real scenario, you might inspect/backup existing data before removing.
    # For this task, failure simulation implies data is lost, so removing is fine.
    docker volume rm "$APP_VOLUME_NAME"
    echo "INFO: Volume '$APP_VOLUME_NAME' removed."
fi
echo "INFO: Creating new Docker volume '$APP_VOLUME_NAME'..."
docker volume create "$APP_VOLUME_NAME"
echo "✅ Volume '$APP_VOLUME_NAME' created/re-created."


# Step 4: Restore data from backup into the volume
echo "INFO: Restoring data from '$LATEST_BACKUP' into volume '$APP_VOLUME_NAME'..."
# Use a temporary busybox container to untar the backup into the volume.
# The volume is mounted at /volume_data_to_restore. Backup is mounted from host.
docker run --rm \
    -v "$APP_VOLUME_NAME:/volume_data_to_restore" \
    -v "$(pwd)/$LATEST_BACKUP:/tmp/backup_to_restore.tar.gz:ro" \
    busybox \
    tar -xzvf /tmp/backup_to_restore.tar.gz -C /volume_data_to_restore

# Verify if data (e.g. store.json) exists in volume after restore (conceptual check)
# This can be done by running another temp container to ls the volume content.
RESTORE_CHECK_OUTPUT=$(docker run --rm -v "$APP_VOLUME_NAME:/data_check:ro" busybox ls -l /data_check)
if echo "$RESTORE_CHECK_OUTPUT" | grep -q "store.json"; then
    echo "✅ Data restoration appears successful. 'store.json' found in volume."
    echo "INFO: Restored volume contents (ls -l):"
    echo "$RESTORE_CHECK_OUTPUT"
else
    echo "❌ ERROR: 'store.json' not found in volume '$APP_VOLUME_NAME' after restoration attempt."
    echo "Volume contents: $RESTORE_CHECK_OUTPUT"
    exit 1
fi


# Step 5: Create docker-compose.restored.yml
echo "INFO: Creating '$RESTORED_COMPOSE_FILE'..."
# This will be very similar to docker-compose.setup.yml, ensuring it uses the *existing* volume.
# Copying setup and ensuring volume is marked as external if created outside compose,
# or just rely on compose using the existing named volume.
# If the volume is explicitly named in the top-level `volumes:` block of compose file,
# Docker Compose will use the existing one if its name matches.
cp "$SETUP_COMPOSE_FILE" "$RESTORED_COMPOSE_FILE"
# Modify if needed, e.g., change container name for restored instance if required.
# For this task, using the same config should be fine as it refers to the explicit volume name.
# sed -i 's/stateful_go_app_container/stateful_go_app_restored_container/' "$RESTORED_COMPOSE_FILE" # Optional
echo "✅ '$RESTORED_COMPOSE_FILE' created (copied from setup template)."


# Step 6: Restart the application using the restored volume
echo "INFO: Starting application using '$RESTORED_COMPOSE_FILE'..."
docker-compose -f "$RESTORED_COMPOSE_FILE" up -d --build # Rebuild if Dockerfile changed, up app
echo "INFO: Waiting for restored application to start (10 seconds)..."
sleep 10

# Step 7: Basic check if app responds
APP_URL="http://localhost:8080" # Assuming port mapping is same
if curl -s "$APP_URL/" > /dev/null; then
    echo "✅ Restored application is responding."
else
    echo "❌ ERROR: Restored application failed to start or is not responding."
    docker-compose -f "$RESTORED_COMPOSE_FILE" logs "$APP_SERVICE_NAME"
    # docker-compose -f "$RESTORED_COMPOSE_FILE" down -v # Cleanup on failure
    exit 1
fi

echo "INFO: Application restoration process complete."
echo "Next steps: Verify data integrity via app's API (e.g., GET /get?key=...)."
exit 0

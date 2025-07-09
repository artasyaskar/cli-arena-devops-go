#!/bin/bash
set -e

COMPOSE_FILE="./resources/docker-compose.setup.yml"
APP_SERVICE_NAME="app_service" # From docker-compose.setup.yml
APP_VOLUME_NAME="restoreapplicationfromfailedkubernetesnodesimulation_app_data_volume" # Default Docker compose naming: <projectdir>_<volumename>
                                                                                  # Or if explicitly named in compose: app_data_volume
                                                                                  # Let's assume the task expects the explicit name `app_data_volume`
                                                                                  # and the docker-compose file defines it as such.
                                                                                  # The compose file I generated uses `app_data_volume` as the key,
                                                                                  # which docker compose CLI will prefix with project name.
                                                                                  # To be robust, we should get the actual volume name.
PROJECT_NAME=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]*//g')
# If the task is run from .../restore_..._simulation/, project name will be restore...simulation
# So, volume name will be restore...simulation_app_data_volume.
# Let's make it simpler by explicitly naming the volume in docker-compose. (I'll update the compose file for this)
# UPDATE: I will modify the docker-compose.setup.yml to use an explicit volume name `app_data_explicit_volume` to simplify this.

APP_EXPLICIT_VOLUME_NAME="app_data_explicit_volume" # Will update docker-compose.setup.yml for this

BACKUP_DIR="./resources/backups"
APP_URL="http://localhost:8080"

echo "INFO: Starting setup: Build/run app, add data, create backup."

# Step 1: Ensure backup directory exists
mkdir -p "$BACKUP_DIR"
echo "INFO: Backup directory is $BACKUP_DIR"

# Step 2: Build and start the application
echo "INFO: Building and starting application using $COMPOSE_FILE..."
# Use explicit project name to make volume name predictable if not explicitly named.
# docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d --build
# With explicit volume name in compose file, -p is less critical for volume name.
docker-compose -f "$COMPOSE_FILE" up -d --build

echo "INFO: Waiting for application to start (10 seconds)..."
sleep 10

# Check if app is responsive
if ! curl -s "$APP_URL/" > /dev/null; then
    echo "❌ ERROR: Application failed to start or is not responding."
    docker-compose -f "$COMPOSE_FILE" logs "$APP_SERVICE_NAME"
    docker-compose -f "$COMPOSE_FILE" down -v # Clean up on failure
    exit 1
fi
echo "✅ Application started successfully."

# Step 3: Add some initial data to the app
echo "INFO: Adding initial data to the application..."
curl -s -X POST "$APP_URL/set?key=fruit&value=apple"
curl -s -X POST "$APP_URL/set?key=color&value=red"
curl -s -X POST "$APP_URL/set?key=city&value=testville"
echo # Newline after curl outputs
echo "✅ Initial data added."
# Verify data
echo "INFO: Verifying data..."
if ! curl -s "$APP_URL/get?key=fruit" | grep -q "apple"; then
    echo "❌ ERROR: Failed to verify data for key 'fruit'."
    docker-compose -f "$COMPOSE_FILE" down -v
    exit 1
fi
if ! curl -s "$APP_URL/get?key=city" | grep -q "testville"; then
    echo "❌ ERROR: Failed to verify data for key 'city'."
    docker-compose -f "$COMPOSE_FILE" down -v
    exit 1
fi
echo "✅ Data verified in running app."


# Step 4: Simulate taking a backup of the Docker volume
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_FILE="$BACKUP_DIR/app_data_backup_${TIMESTAMP}.tar.gz"

echo "INFO: Taking backup of volume '$APP_EXPLICIT_VOLUME_NAME' to '$BACKUP_FILE'..."

# Use a temporary busybox container to access and tar the volume data.
# The volume must be mounted to this temporary container.
# The backup is created *from the perspective of the volume's content*.
# `docker cp` could also work if we know the path *inside* the app container, but this is more generic for volumes.
docker run --rm \
    -v "${APP_EXPLICIT_VOLUME_NAME}:/volume_data_to_backup:ro" \
    -v "$(pwd)/$BACKUP_DIR:/backups_on_host" \
    busybox \
    tar -czvf "/backups_on_host/app_data_backup_${TIMESTAMP}.tar.gz" -C /volume_data_to_backup .

# Check if backup file was created and is not empty
if [ -s "$BACKUP_FILE" ]; then
    echo "✅ Backup created successfully: $BACKUP_FILE"
    echo "INFO: Contents of backup (first few lines of tar -tvf):"
    tar -tvf "$BACKUP_FILE" | head -n 5 || echo " (Could not list tar contents)"
else
    echo "❌ ERROR: Backup file '$BACKUP_FILE' was not created or is empty."
    docker-compose -f "$COMPOSE_FILE" down -v
    exit 1
fi

echo "INFO: Setup complete. Application is running with initial data, and a backup has been taken."
echo "You can now proceed to simulate failure and test restoration."
# Note: The application is left running by this script.
# The test/verify script will handle stopping it to simulate failure.

exit 0

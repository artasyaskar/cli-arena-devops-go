#!/bin/bash
set -e

FIXED_DOCKERFILE="Dockerfile.fixed"
IMAGE_NAME="fixed-app-test:latest"
CONTAINER_NAME="fixed-app-container-test"
APP_RESOURCES_PATH="./resources/app" # Path to app source for docker build context

# Check 1: Dockerfile.fixed exists
if [ ! -f "$FIXED_DOCKERFILE" ]; then
  echo "❌ FAIL: Required output file '$FIXED_DOCKERFILE' not found."
  exit 1
fi
echo "✅ PASS: '$FIXED_DOCKERFILE' exists."

# Cleanup function
cleanup() {
  echo "INFO: Cleaning up..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT # Ensure cleanup happens on script exit, success or failure (after first error if set -e)

# Check 2: Build the Docker image using Dockerfile.fixed
echo "INFO: Attempting to build '$FIXED_DOCKERFILE' as image '$IMAGE_NAME'..."
if ! docker build -f "$FIXED_DOCKERFILE" -t "$IMAGE_NAME" "$APP_RESOURCES_PATH"; then
  echo "❌ FAIL: Docker image build failed for '$FIXED_DOCKERFILE'."
  exit 1
fi
echo "✅ PASS: Docker image '$IMAGE_NAME' built successfully."

# Check 3: Run the container and check application response
echo "INFO: Running container '$CONTAINER_NAME' from image '$IMAGE_NAME'..."
# Run detached, then exec/check, then stop and remove
# Map port 8080 (app's default) to a host port (e.g., 8088 for testing)
docker run -d --name "$CONTAINER_NAME" -p 8088:8080 "$IMAGE_NAME"
echo "INFO: Waiting for container to start (5 seconds)..."
sleep 5

# Check if container is running
if ! docker ps -f name="^/${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "❌ FAIL: Container '$CONTAINER_NAME' did not start correctly."
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# Check application response on /
RESPONSE_ROOT=$(curl -s http://localhost:8088/)
EXPECTED_RESPONSE="Hello from a Go app!"
if ! echo "$RESPONSE_ROOT" | grep -q "$EXPECTED_RESPONSE"; then
  echo "❌ FAIL: Application did not respond as expected on /."
  echo "Expected to contain: '$EXPECTED_RESPONSE'"
  echo "Got: '$RESPONSE_ROOT'"
  docker logs "$CONTAINER_NAME"
  exit 1
fi
echo "✅ PASS: Application responded correctly on /."

# Check 4: Effective user inside container is non-root
# This can be checked by `docker exec <container> id -u` or by checking app logs if it prints UID
# The sample app prints UID to its logs.
APP_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1) # Get both stdout and stderr
EFFECTIVE_UID_FROM_LOG=$(echo "$APP_LOGS" | grep "Running as User:" | sed -n 's/.*UID: \([0-9]*\).*/\1/p' | tail -n1)

# More robust check: exec id -u
EFFECTIVE_UID_EXEC=$(docker exec "$CONTAINER_NAME" id -u)

if [ -z "$EFFECTIVE_UID_EXEC" ]; then
    echo "❌ FAIL: Could not determine effective UID in container using 'docker exec'."
    exit 1
fi

if [ "$EFFECTIVE_UID_EXEC" -eq 0 ]; then
  echo "❌ FAIL: Container is running as root (UID $EFFECTIVE_UID_EXEC found via exec)."
  echo "App logs UID line: $(echo "$APP_LOGS" | grep "Running as User:")"
  exit 1
else
  echo "✅ PASS: Container is running as non-root (UID $EFFECTIVE_UID_EXEC found via exec)."
  if [ -n "$EFFECTIVE_UID_FROM_LOG" ] && [ "$EFFECTIVE_UID_FROM_LOG" -ne 0 ]; then
    echo "✅ PASS: App log also indicates non-root UID ($EFFECTIVE_UID_FROM_LOG)."
  elif [ -n "$EFFECTIVE_UID_FROM_LOG" ];
    echo "WARN: App log indicates UID $EFFECTIVE_UID_FROM_LOG, but exec check is primary."
  fi
fi

# Check 5: Image size is reasonably small
IMAGE_SIZE_BYTES=$(docker inspect --format='{{.Size}}' "$IMAGE_NAME")
# Convert to MB for easier understanding, typical small Go Alpine image is < 20-30MB.
# Let's set a threshold, e.g., 30MB.
MAX_EXPECTED_SIZE_BYTES=$((30 * 1024 * 1024)) # 30 MB

if [ "$IMAGE_SIZE_BYTES" -gt "$MAX_EXPECTED_SIZE_BYTES" ]; then
  SIZE_MB=$(echo "scale=2; $IMAGE_SIZE_BYTES / (1024*1024)" | bc)
  MAX_MB=$(echo "scale=2; $MAX_EXPECTED_SIZE_BYTES / (1024*1024)" | bc)
  echo "❌ WARN: Image size ($SIZE_MB MB) is larger than expected maximum ($MAX_MB MB)."
  echo "   This might indicate build artifacts weren't properly excluded or a non-minimal base image was used."
  # Not a hard fail for this task, but a strong warning. Task success criteria mentions "reasonably small".
else
  SIZE_MB=$(echo "scale=2; $IMAGE_SIZE_BYTES / (1024*1024)" | bc)
  echo "✅ PASS: Image size ($SIZE_MB MB) is reasonably small."
fi


echo "------------------------------------------"
echo "✅✅✅ All multi-stage Docker build verification tests passed (or passed with warnings)."
# Note: cleanup is handled by trap
exit 0

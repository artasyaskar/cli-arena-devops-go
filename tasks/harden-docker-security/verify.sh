#!/bin/bash

HARDENED_DOCKERFILE="Dockerfile.hardened"
IMAGE_NAME="hardened-app-test:latest"
CONTAINER_NAME="hardened-app-container-test"

# Check 0: Dockerfile.hardened exists
if [ ! -f "$HARDENED_DOCKERFILE" ]; then
  echo "❌ FAIL: Required output file '$HARDENED_DOCKERFILE' not found."
  exit 1
fi
echo "✅ PASS: '$HARDENED_DOCKERFILE' exists."

# Check 1: Does not run as ROOT user
if grep -q "^USER root" "$HARDENED_DOCKERFILE" || ! grep -q "^USER appuser" "$HARDENED_DOCKERFILE"; then
  echo "❌ FAIL: Dockerfile should specify a non-root user (e.g., 'USER appuser') and not 'USER root' before CMD."
  # exit 1 # Commenting out exit 1 to allow further checks
else
  echo "✅ PASS: Dockerfile specifies a non-root user."
fi

# Check 2: Package installs use specific versions (approximate check)
# This checks if 'apk add' contains ~ or = for version pinning.
if ! grep -E "apk add .*(--no-cache )?(curl~=|curl=[0-9]|git~=|git=[0-9])" "$HARDENED_DOCKERFILE"; then
  echo "❌ WARN: Package installations in 'apk add' might not be pinned to specific versions (e.g., curl=1.2.3 or curl~=1.2)."
  # exit 1
else
  echo "✅ PASS: Package installations appear to be pinned."
fi

# Check 3: HEALTHCHECK instruction is present
if ! grep -q "^HEALTHCHECK" "$HARDENED_DOCKERFILE"; then
  echo "❌ FAIL: HEALTHCHECK instruction is missing."
  # exit 1
else
  echo "✅ PASS: HEALTHCHECK instruction is present."
fi

# Check 4: apt-get update uses --no-cache or cleans up (apk specific)
if ! grep -q "apk add --no-cache" "$HARDENED_DOCKERFILE" && ! grep -q "rm -rf /var/cache/apk/*" "$HARDENED_DOCKERFILE"; then
  echo "❌ FAIL: 'apk add' does not use '--no-cache' or clean up apk cache."
  # exit 1
else
  echo "✅ PASS: apk cache seems to be handled (either --no-cache or rm)."
fi

# Check 5: No obvious hardcoded secrets like API_KEY=dummy_value
if grep -q "API_KEY=dummy_value_replace_me_in_production" "$HARDENED_DOCKERFILE"; then
  echo "❌ FAIL: Hardcoded 'API_KEY=dummy_value_replace_me_in_production' found. This should be removed or handled by ARG/ENV."
  # exit 1
elif ! grep -q "ARG API_KEY" "$HARDENED_DOCKERFILE" && ! grep -q "ENV API_KEY" "$HARDENED_DOCKERFILE"; then
  echo "❌ WARN: API_KEY handling (ARG/ENV) not explicitly found. Ensure it's managed securely if used."
else
  echo "✅ PASS: No hardcoded 'API_KEY=dummy_value_replace_me_in_production'. API_KEY seems handled by ARG/ENV."
fi

# Check 6: COPY commands use --chown if a non-root user is configured
if grep -q "^USER appuser" "$HARDENED_DOCKERFILE" && ! grep -E "COPY --chown=appuser:appgroup" "$HARDENED_DOCKERFILE"; then
  echo "❌ WARN: 'COPY' commands might be missing '--chown=appuser:appgroup' after setting up 'appuser'."
  # exit 1
else
  echo "✅ PASS: 'COPY' commands appear to use '--chown' where appropriate or non-root user not yet primary focus."
fi

# Check 7: Build the Docker image
echo "Attempting to build the hardened Dockerfile: $HARDENED_DOCKERFILE..."
if ! docker build -f "$HARDENED_DOCKERFILE" -t "$IMAGE_NAME" --build-arg API_KEY="test_verify_key" ./resources; then
  echo "❌ FAIL: Docker image build failed for '$HARDENED_DOCKERFILE'."
  # Try to clean up image if it was partially built
  docker rmi "$IMAGE_NAME" 2>/dev/null || true
  exit 1
fi
echo "✅ PASS: Docker image '$IMAGE_NAME' built successfully."

# Check 8: Run the container and check application response & user
echo "Running container '$CONTAINER_NAME' from image '$IMAGE_NAME'..."
# Run detached, then exec, then stop and remove
docker run -d --name "$CONTAINER_NAME" -e APP_USER="appuser" -e API_KEY="runtime_key_verify" -p 8081:8080 "$IMAGE_NAME"
# Give container a moment to start
sleep 5

# Check if container is running
if ! docker ps -f name="$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "❌ FAIL: Container '$CONTAINER_NAME' did not start correctly."
    docker logs "$CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker rmi "$IMAGE_NAME" 2>/dev/null || true
    exit 1
fi

# Check 8a: Application responds on /
RESPONSE_ROOT=$(curl -s http://localhost:8081/)
if ! echo "$RESPONSE_ROOT" | grep -q "Hello from the Go web server!"; then
  echo "❌ FAIL: Application did not respond as expected on /."
  echo "Response: $RESPONSE_ROOT"
  # exit 1 # Don't exit yet, run all checks
else
  echo "✅ PASS: Application responded correctly on /."
fi

# Check 8b: Check API_KEY usage (set via runtime env var)
RESPONSE_API_KEY_USAGE=$(curl -s http://localhost:8081/check_api_key_usage)
if ! echo "$RESPONSE_API_KEY_USAGE" | grep -q "API_KEY is configured for use by the application."; then
  echo "❌ FAIL: Application does not seem to use the runtime API_KEY correctly."
  echo "Response: $RESPONSE_API_KEY_USAGE"
else
  echo "✅ PASS: Application seems to use the runtime API_KEY correctly."
fi


# Check 8c: Effective user inside container is non-root
# We check this by inspecting the output of `whoami` or checking process user
# For the Go app, we added an env var APP_USER and check os.Getuid() in main.go which prints to log
# More reliable: exec into container and check UID
EFFECTIVE_UID=$(docker exec "$CONTAINER_NAME" id -u)
if [ "$EFFECTIVE_UID" -eq 0 ]; then
  echo "❌ FAIL: Container is running as root (UID $EFFECTIVE_UID)."
  # exit 1
elif [ -z "$EFFECTIVE_UID" ]; then
  echo "❌ FAIL: Could not determine effective UID in container."
else
  echo "✅ PASS: Container is running as non-root (UID $EFFECTIVE_UID)."
fi

# Check 9: Healthcheck status (if supported by Docker version and image)
# This requires the container to be running for a bit.
echo "Checking health status of container '$CONTAINER_NAME'..."
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME")
# Give it a few more seconds for health check to potentially pass
if [ "$HEALTH_STATUS" != "healthy" ]; then
    sleep 10 # wait for health check
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME")
fi

if [ "$HEALTH_STATUS" = "healthy" ]; then
  echo "✅ PASS: Container health status is 'healthy'."
elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
  echo "❌ FAIL: Container health status is 'unhealthy'."
  # exit 1
else
  echo "❌ WARN: Container health status is '$HEALTH_STATUS' (may be starting or no healthcheck in image)."
fi

# Cleanup
echo "Stopping and removing container '$CONTAINER_NAME'..."
docker stop "$CONTAINER_NAME" >/dev/null
docker rm "$CONTAINER_NAME" >/dev/null
echo "Removing image '$IMAGE_NAME'..."
docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true # allow failure if other tags exist

# Final simulated 'docker scan' check (conceptual)
# Real `docker scan` requires login to Snyk or other provider.
# We'll simulate by checking for common bad patterns NOT caught above.
echo "Simulating security scan for obvious remaining issues..."
if grep -Ei 'expos(e|ed)_key|password=|secret=' "$HARDENED_DOCKERFILE"; then
    echo "❌ WARN: Potential hardcoded secrets found by basic grep scan (e.g., password=, exposed_key=)."
else
    echo "✅ PASS: Basic grep scan for obvious secrets passed."
fi

if grep -i "FROM .*latest" "$HARDENED_DOCKERFILE"; then
    echo "❌ WARN: Base image uses 'latest' tag. Pin to a specific version/digest for production."
else
    echo "✅ PASS: Base image does not use 'latest' tag."
fi

echo "------------------------------------------"
echo "Verification complete. Check log for FAIL/WARN messages."
# Check for any FAIL messages in this script's output to determine final status
# This is a simple way, a more robust way would be a counter.
if [[ $(grep -c "❌ FAIL:" verify.log) -gt 0 ]]; then
    echo "🔴 Overall Status: FAILED (see messages above)"
    exit 1
else
    echo "🟢 Overall Status: PASSED (or passed with warnings)"
    exit 0
fi

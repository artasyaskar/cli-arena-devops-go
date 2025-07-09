#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"
DOCKER_COMPOSE_CANARY_EXPECTED="$TASK_ROOT_DIR/docker-compose.canary.yml"
SET_TRAFFIC_SCRIPT_EXPECTED="$TASK_ROOT_DIR/set_traffic_split.sh"
NGINX_CONF_MODIFIED_EXPECTED="$TASK_ROOT_DIR/resources/nginx/nginx.conf"
NGINX_CONF_ORIGINAL_V1="$TASK_ROOT_DIR/resources/nginx/nginx.v1.conf" # For restoring if needed

echo "INFO: Starting test for 'implement_canary_deployment_strategy_docker' task..."
echo "Current directory: $(pwd)"
# Ensure we are in the task's root directory
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the 'implement_canary_deployment_strategy_docker' task directory."
    exit 1
fi


# Clean up any artifacts from previous runs
echo "INFO: Cleaning up artifacts from previous test runs..."
rm -f "$DOCKER_COMPOSE_CANARY_EXPECTED"
rm -f "$SET_TRAFFIC_SCRIPT_EXPECTED"
# Restore original nginx.conf before solution runs, so solution always starts from a known state.
if [ -f "$NGINX_CONF_ORIGINAL_V1" ]; then
    cp -f "$NGINX_CONF_ORIGINAL_V1" "$NGINX_CONF_MODIFIED_EXPECTED"
    echo "INFO: Restored nginx.conf from nginx.v1.conf."
else
    # Fallback: if nginx.v1.conf is missing, ensure nginx.conf is at least a placeholder
    # This state should ideally match what solution expects as input for nginx.conf
    cat << EOF_NGINX_PLACEHOLDER > "$NGINX_CONF_MODIFIED_EXPECTED"
events {
    worker_connections 1024;
}
http {
    upstream app_v1_backend {
        server app_v1:8081;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://app_v1_backend;
        }
    }
}
EOF_NGINX_PLACEHOLDER
    echo "INFO: nginx.v1.conf not found, created a placeholder nginx.conf."

fi

# Stop and remove any running containers from a previous failed run
if [ -f "$DOCKER_COMPOSE_CANARY_EXPECTED" ]; then # If a previous solution run created it
    echo "INFO: Attempting to stop services from a previous run (if any)..."
    docker-compose -f "$DOCKER_COMPOSE_CANARY_EXPECTED" down --remove-orphans > /dev/null 2>&1 || true
fi
# Also try with the original v1 compose file if it exists
if [ -f "$TASK_ROOT_DIR/resources/docker-compose.v1.yml" ]; then
    docker-compose -f "$TASK_ROOT_DIR/resources/docker-compose.v1.yml" down --remove-orphans > /dev/null 2>&1 || true
fi


# Make scripts executable
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Run the solution script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running solution script..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script failed to execute."
    exit 1
fi
echo "✅ Solution script executed successfully."

# Check if solution created the required files
if [ ! -f "$DOCKER_COMPOSE_CANARY_EXPECTED" ]; then
    echo "❌ TEST FAIL: Solution did not create '$DOCKER_COMPOSE_CANARY_EXPECTED'."
    exit 1
fi
if [ ! -f "$SET_TRAFFIC_SCRIPT_EXPECTED" ]; then
    echo "❌ TEST FAIL: Solution did not create '$SET_TRAFFIC_SCRIPT_EXPECTED'."
    exit 1
fi
if ! grep -q "split_clients" "$NGINX_CONF_MODIFIED_EXPECTED"; then
    echo "❌ TEST FAIL: Nginx config '$NGINX_CONF_MODIFIED_EXPECTED' does not seem to be modified for split_clients."
    exit 1
fi
echo "✅ Solution created required files and modified Nginx configuration."


# Step 2: Run the verification script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running verification script..."
echo "---------------------------------------------------------------------"
# The verify script handles docker-compose up/down and all checks.
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    # Verify script should handle its own cleanup (docker-compose down) on failure if possible.
    # If not, we might have lingering containers.
    exit 1
fi
echo "✅ Verification script executed successfully and confirmed canary deployment functionality."


# Step 3: Final cleanup (verify script should have done this, but as a safeguard)
echo "---------------------------------------------------------------------"
echo "INFO: STEP 3 - Final cleanup..."
echo "---------------------------------------------------------------------"
if [ -f "$DOCKER_COMPOSE_CANARY_EXPECTED" ]; then
    docker-compose -f "$DOCKER_COMPOSE_CANARY_EXPECTED" down --remove-orphans > /dev/null 2>&1 || true
fi
rm -f "$DOCKER_COMPOSE_CANARY_EXPECTED"
rm -f "$SET_TRAFFIC_SCRIPT_EXPECTED"
# Restore original nginx.conf again for a clean state for next test run
if [ -f "$NGINX_CONF_ORIGINAL_V1" ]; then
    cp -f "$NGINX_CONF_ORIGINAL_V1" "$NGINX_CONF_MODIFIED_EXPECTED"
fi
echo "✅ Cleanup complete."

echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'implement_canary_deployment_strategy_docker' task test completed successfully."
echo "---------------------------------------------------------------------"

exit 0

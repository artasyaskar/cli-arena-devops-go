#!/usr/bin/env bash
set -e

DOCKER_COMPOSE_CANARY="docker-compose.canary.yml"
SET_TRAFFIC_SCRIPT="./set_traffic_split.sh" # Assumes it's in the task root with verify.sh
NGINX_CONF_PATH="./resources/nginx/nginx.conf" # Path for set_traffic_script

# Check if required files from solution exist
if [ ! -f "$DOCKER_COMPOSE_CANARY" ]; then
    echo "❌ FAIL: Required file '$DOCKER_COMPOSE_CANARY' not found. Run solution first."
    exit 1
fi
if [ ! -f "$SET_TRAFFIC_SCRIPT" ]; then
    echo "❌ FAIL: Required script '$SET_TRAFFIC_SCRIPT' not found. Run solution first."
    exit 1
fi
if [ ! -f "$NGINX_CONF_PATH" ]; then
    echo "❌ FAIL: Nginx configuration '$NGINX_CONF_PATH' not found."
    exit 1
fi

# Ensure set_traffic_split.sh is executable
chmod +x "$SET_TRAFFIC_SCRIPT"

# Function to make requests and count responses from v1 and v2
check_traffic_split() {
    local total_requests=$1
    local expected_v1_ratio=$2 # e.g., 0.9 for 90%
    local expected_v2_ratio=$3 # e.g., 0.1 for 10%
    local tolerance=0.20 # Allow 20% tolerance for small number of requests

    echo "INFO: Checking traffic split for v1_ratio=$expected_v1_ratio, v2_ratio=$expected_v2_ratio over $total_requests requests..."

    local v1_count=0
    local v2_count=0

    for i in $(seq 1 $total_requests); do
        # Use curl with a unique query param to try and bypass some caching and vary the split_clients input
        response_version=$(curl -s "http://localhost:80/version?q=$RANDOM")
        # Alternative: check the X-Upstream-Target header if solution added it
        # response_header=$(curl -s -I "http://localhost:80/?q=$RANDOM" | grep -i "X-Upstream-Target:")
        # if echo "$response_header" | grep -q "app_v1_backend"; then

        if [[ "$response_version" == "App version v1" ]]; then
            v1_count=$((v1_count + 1))
        elif [[ "$response_version" == "App version v2" ]]; then
            v2_count=$((v2_count + 1))
        else
            echo "WARN: Unexpected response from /version: $response_version"
        fi
        sleep 0.05 # Small delay between requests
    done

    actual_v1_ratio=$(echo "scale=2; $v1_count / $total_requests" | bc)
    actual_v2_ratio=$(echo "scale=2; $v2_count / $total_requests" | bc)

    echo "INFO: Actual distribution: v1_hits=$v1_count (${actual_v1_ratio}), v2_hits=$v2_count (${actual_v2_ratio})"

    # Check if actual ratios are within tolerance of expected ratios
    # bc doesn't handle floats directly in comparisons well, so compare integers or use awk
    v1_ok=$(awk -v actual="$actual_v1_ratio" -v expected="$expected_v1_ratio" -v tol="$tolerance" \
        'BEGIN { exit (actual >= expected - tol && actual <= expected + tol) ? 0 : 1 }')
    v2_ok=$(awk -v actual="$actual_v2_ratio" -v expected="$expected_v2_ratio" -v tol="$tolerance" \
        'BEGIN { exit (actual >= expected - tol && actual <= expected + tol) ? 0 : 1 }')

    if $v1_ok && $v2_ok; then
        echo "✅ PASS: Traffic split is approximately as expected (v1: $actual_v1_ratio, v2: $actual_v2_ratio)."
        return 0
    else
        echo "❌ FAIL: Traffic split NOT as expected (v1: $actual_v1_ratio vs $expected_v1_ratio, v2: $actual_v2_ratio vs $expected_v2_ratio)."
        return 1
    fi
}


# Main verification steps
echo "INFO: Starting Docker services using $DOCKER_COMPOSE_CANARY..."
docker-compose -f "$DOCKER_COMPOSE_CANARY" up -d --build
echo "INFO: Waiting for services to start (15 seconds)..."
sleep 15 # Give time for services to initialize

# Check if Nginx is up
if ! curl -s http://localhost:80/ > /dev/null; then
    echo "❌ FAIL: Nginx does not seem to be responding on port 80."
    docker-compose -f "$DOCKER_COMPOSE_CANARY" logs nginx
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi
echo "✅ PASS: Nginx is responding."

# Test 1: Initial 90/10 split (as set by solution.sh)
echo "INFO: === Test 1: Verifying initial 90/10 traffic split ==="
if ! check_traffic_split 50 0.9 0.1; then
    # Failure message printed by function
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi

# Test 2: Change split to 0/100 (all to v2) using set_traffic_split.sh
echo "INFO: === Test 2: Setting traffic to 0/100 (all to v2) ==="
"$SET_TRAFFIC_SCRIPT" 0 100
echo "INFO: Waiting for Nginx to reload (5 seconds)..."
sleep 5
if ! check_traffic_split 20 0.0 1.0; then
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi

# Test 3: Change split to 100/0 (all to v1, rollback) using set_traffic_split.sh
echo "INFO: === Test 3: Setting traffic to 100/0 (all to v1) ==="
"$SET_TRAFFIC_SCRIPT" 100 0
echo "INFO: Waiting for Nginx to reload (5 seconds)..."
sleep 5
if ! check_traffic_split 20 1.0 0.0; then
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi

# Test 4: Change split to 50/50 using set_traffic_split.sh
echo "INFO: === Test 4: Setting traffic to 50/50 ==="
"$SET_TRAFFIC_SCRIPT" 50 50
echo "INFO: Waiting for Nginx to reload (5 seconds)..."
sleep 5
if ! check_traffic_split 50 0.5 0.5; then
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi

# Test 5: Check direct access to v1 and v2 version endpoints
echo "INFO: === Test 5: Verifying direct access to /v1/version and /v2/version ==="
v1_direct_response=$(curl -s http://localhost:80/v1/version)
if [[ "$v1_direct_response" != "App version v1" ]]; then
    echo "❌ FAIL: Direct access to /v1/version returned: $v1_direct_response"
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi
echo "✅ PASS: Direct access to /v1/version is correct."

v2_direct_response=$(curl -s http://localhost:80/v2/version)
if [[ "$v2_direct_response" != "App version v2" ]]; then
    echo "❌ FAIL: Direct access to /v2/version returned: $v2_direct_response"
    docker-compose -f "$DOCKER_COMPOSE_CANARY" down
    exit 1
fi
echo "✅ PASS: Direct access to /v2/version is correct."


echo "------------------------------------------"
echo "✅✅✅ All canary deployment verification tests passed."
echo "------------------------------------------"

# Cleanup
echo "INFO: Stopping and removing Docker services..."
docker-compose -f "$DOCKER_COMPOSE_CANARY" down
# Restore original nginx.conf if solution modified it, so test can be rerun.
# The solution script overwrites it, so this is more for local testing convenience.
# cp -f "./resources/nginx/nginx.v1.conf" "./resources/nginx/nginx.conf"
# For the agent, the solution script will run each time, so this is not strictly necessary.
echo "INFO: Verification complete."
exit 0

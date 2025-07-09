#!/bin/bash
set -e

APP_MAIN_GO="./resources/app/main.go"
FLUENT_CONF="./resources/fluentd/fluent.conf"
DOCKER_COMPOSE_YAML="./resources/docker-compose.yml" # Modified by solution
FLUENTD_LOG_DIR_HOST="./resources/fluentd_logs" # Host path for Fluentd file output volume
FLUENTD_LOG_FILE_NAME="app.log.json" # Name of the file inside fluentd_logs (may have date/time parts from fluentd)
                                     # The solution uses app.log.json directly for path.

echo "INFO: Starting verification for Centralized Logging with Fluentd task."

# Check 1: Ensure solution has modified/created required files
if ! grep -q "json.Marshal(entry)" "$APP_MAIN_GO"; then # Basic check for JSON logging attempt
    echo "❌ FAIL: Go app '$APP_MAIN_GO' does not seem to be modified for JSON logging."
    exit 1
fi
if [ ! -s "$FLUENT_CONF" ] || ! grep -q "<source>" "$FLUENT_CONF" || ! grep -q "<match docker.go_app.**>" "$FLUENT_CONF"; then
    echo "❌ FAIL: Fluentd config '$FLUENT_CONF' is empty or missing key sections."
    exit 1
fi
if ! grep -q "image: fluent/fluentd" "$DOCKER_COMPOSE_YAML" || \
   ! grep -q "image: alpine/socat" "$DOCKER_COMPOSE_YAML" || \
   ! grep -q "driver: \"fluentd\"" "$DOCKER_COMPOSE_YAML"; then
    echo "❌ FAIL: '$DOCKER_COMPOSE_YAML' does not seem to be configured correctly for Fluentd, socat, or app logging driver."
    exit 1
fi
echo "✅ PASS: Required files appear to be modified/created correctly by the solution."

# Prepare host directory for Fluentd logs
mkdir -p "$FLUENTD_LOG_DIR_HOST"
# Ensure it's writable by fluentd container (which might run as non-root 'fluent' user, UID 1000 typically)
# For simplicity in task, use 777. In prod, match UID/GID.
chmod 777 "$FLUENTD_LOG_DIR_HOST"
# Clean up old log files from previous runs
rm -f "$FLUENTD_LOG_DIR_HOST/$FLUENTD_LOG_FILE_NAME"* # Handles time-sliced files too if pattern matches

# Cleanup function
cleanup() {
  echo "INFO: Cleaning up Docker environment..."
  docker-compose -f "$DOCKER_COMPOSE_YAML" down -v --remove-orphans >/dev/null 2>&1 || true
  # rm -f "$FLUENTD_LOG_DIR_HOST/$FLUENTD_LOG_FILE_NAME"* # Clean logs again
}
trap cleanup EXIT


# Step 2: Start services using Docker Compose
echo "INFO: Building and starting services with 'docker-compose -f $DOCKER_COMPOSE_YAML up -d --build'..."
if ! docker-compose -f "$DOCKER_COMPOSE_YAML" up -d --build; then
    echo "❌ FAIL: 'docker-compose up' failed."
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs app fluentd netcat_listener
    exit 1 # Trap will cleanup
fi
echo "INFO: Services started. Waiting for initialization (20 seconds)..."
sleep 20 # Time for Fluentd to start, app to connect logging driver, etc.

# Step 3: Send requests to the Go app to generate logs
echo "INFO: Sending requests to Go app to generate different types of logs..."
curl -s "http://localhost:8080/" > /dev/null # Info log
sleep 0.5
curl -s "http://localhost:8080/error" > /dev/null # Error log
sleep 0.5
curl -s "http://localhost:8080/skip" > /dev/null # Skippable info log
sleep 0.5
curl -s "http://localhost:8080/another" > /dev/null # Another info log
echo "INFO: Requests sent. Waiting for logs to process (10 seconds)..."
sleep 10 # Allow time for Fluentd to process and flush buffers

# Step 4 & 5: Verify logs in Fluentd output file and netcat listener
# This is complex. We need to check for structure, enrichment, filtering.
# We'll check both the file output and netcat logs.

LOG_VERIFICATION_PASSED=true

# Find the actual log file Fluentd created (might have buffer timestamps)
# The solution's fluent.conf uses a path that might be part of a time-sliced filename.
# For `path /fluentd/log/app.log.json`, if buffer is not path-modifying, it's just that file.
# Let's assume the file is directly `app.log.json` or the first one matching the pattern.
ACTUAL_LOG_FILE=$(find "$FLUENTD_LOG_DIR_HOST" -name "$FLUENTD_LOG_FILE_NAME*" -print -quit)

if [ -z "$ACTUAL_LOG_FILE" ] || [ ! -s "$ACTUAL_LOG_FILE" ]; then
    echo "❌ FAIL: Fluentd output log file '$FLUENTD_LOG_DIR_HOST/$FLUENTD_LOG_FILE_NAME*' not found or is empty."
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs fluentd
    LOG_VERIFICATION_PASSED=false
else
    echo "INFO: Verifying logs in Fluentd output file: $ACTUAL_LOG_FILE"
    # Check for JSON structure (very basic: check for '{' and '}')
    if ! grep -q '[{}]' "$ACTUAL_LOG_FILE"; then
        echo "❌ FAIL: Logs in '$ACTUAL_LOG_FILE' do not appear to be JSON."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Logs in '$ACTUAL_LOG_FILE' contain JSON-like characters."
    fi

    # Check for enrichment: environment: "development"
    # `jq` is better for this, but might not be available. Using grep.
    if ! grep -q '"environment":"development"' "$ACTUAL_LOG_FILE"; then
        echo "❌ FAIL: Enrichment 'environment:development' not found in '$ACTUAL_LOG_FILE'."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Enrichment 'environment:development' found."
    fi

    # Check for conditional enrichment: priority: "high" for error logs
    # And ensure it's NOT on info logs.
    if grep -q '"level":"error"' "$ACTUAL_LOG_FILE" && ! grep '{"level":"error".*"priority":"high"' "$ACTUAL_LOG_FILE"; then
        echo "❌ FAIL: 'priority:high' not found for an error log in '$ACTUAL_LOG_FILE'."
        LOG_VERIFICATION_PASSED=false
    elif ! grep -q '"level":"error"' "$ACTUAL_LOG_FILE"; then
        echo "INFO: No error logs found in '$ACTUAL_LOG_FILE' to verify priority:high. (This might be ok if /error was not hit or logged differently)"
    else
        echo "✅ PASS: 'priority:high' seems correctly applied for error logs."
    fi
    if grep '{"level":"info".*"priority":"high"' "$ACTUAL_LOG_FILE"; then
        echo "❌ FAIL: 'priority:high' found on an info log in '$ACTUAL_LOG_FILE'."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: 'priority:high' not found on info logs, as expected."
    fi


    # Check for filtering: "skip_this_log_message" should NOT be present
    if grep -q "skip_this_log_message" "$ACTUAL_LOG_FILE"; then
        echo "❌ FAIL: Filter failed: 'skip_this_log_message' found in '$ACTUAL_LOG_FILE'."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Filter successful: 'skip_this_log_message' not found."
    fi
    # Count lines to ensure some logs are present (at least 2 expected: root, another; error makes 3)
    NUM_LOG_LINES_FILE=$(wc -l < "$ACTUAL_LOG_FILE")
    if [ "$NUM_LOG_LINES_FILE" -lt 2 ]; then # Expecting at least / and /another. /error makes 3. /skip is filtered.
        echo "❌ FAIL: Not enough log lines found in '$ACTUAL_LOG_FILE'. Expected at least 2, got $NUM_LOG_LINES_FILE."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Sufficient number of log lines ($NUM_LOG_LINES_FILE) found in file output."
    fi
fi

# Verify logs from netcat listener
echo "INFO: Verifying logs from netcat_listener (docker logs nc_listener)..."
NC_LOGS=$(docker-compose -f "$DOCKER_COMPOSE_YAML" logs netcat_listener 2>&1 || echo "ERROR reading nc_listener logs")

if echo "$NC_LOGS" | grep -q "ERROR reading nc_listener logs"; then
    echo "❌ FAIL: Could not read logs from netcat_listener."
    LOG_VERIFICATION_PASSED=false
elif ! echo "$NC_LOGS" | grep -q '[{}]'; then
    echo "❌ FAIL: Logs from netcat_listener do not appear to be JSON."
    LOG_VERIFICATION_PASSED=false
else
    echo "✅ PASS: Logs from netcat_listener contain JSON-like characters."
    # Similar checks as for the file
    if ! echo "$NC_LOGS" | grep -q '"environment":"development"'; then
        echo "❌ FAIL: Enrichment 'environment:development' not found in netcat_listener logs."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Enrichment 'environment:development' found in netcat_listener logs."
    fi

    if echo "$NC_LOGS" | grep -q '"level":"error"' && ! echo "$NC_LOGS" | grep '{"level":"error".*"priority":"high"'; then
        echo "❌ FAIL: 'priority:high' not found for an error log in netcat_listener logs."
        LOG_VERIFICATION_PASSED=false
    elif ! echo "$NC_LOGS" | grep -q '"level":"error"'; then
         echo "INFO: No error logs found in netcat_listener output to verify priority:high."
    else
        echo "✅ PASS: 'priority:high' seems correctly applied for error logs in netcat_listener logs."
    fi
    if echo "$NC_LOGS" | grep '{"level":"info".*"priority":"high"'; then
        echo "❌ FAIL: 'priority:high' found on an info log in netcat_listener logs."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: 'priority:high' not found on info logs in netcat_listener, as expected."
    fi

    if echo "$NC_LOGS" | grep -q "skip_this_log_message"; then
        echo "❌ FAIL: Filter failed: 'skip_this_log_message' found in netcat_listener logs."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Filter successful: 'skip_this_log_message' not found in netcat_listener logs."
    fi
    NUM_LOG_LINES_NC=$(echo "$NC_LOGS" | grep -c '{') # Count lines with '{' as proxy for JSON log lines
     if [ "$NUM_LOG_LINES_NC" -lt 2 ]; then
        echo "❌ FAIL: Not enough log lines found in netcat_listener output. Expected at least 2, got $NUM_LOG_LINES_NC."
        LOG_VERIFICATION_PASSED=false
    else
        echo "✅ PASS: Sufficient number of log lines ($NUM_LOG_LINES_NC) found in netcat_listener output."
    fi
fi


if [ "$LOG_VERIFICATION_PASSED" = false ]; then
    echo "------------------------------------------"
    echo "❌ FAIL: One or more log verification checks failed."
    echo "--- Fluentd File Log Content ($ACTUAL_LOG_FILE): ---"
    cat "$ACTUAL_LOG_FILE" || echo "Could not cat $ACTUAL_LOG_FILE"
    echo "--- Netcat Listener Log Content (docker logs nc_listener): ---"
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs netcat_listener
    echo "--- App Log Content (docker logs go_logging_app): ---"
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs app
    echo "--- Fluentd Log Content (docker logs fluentd_collector): ---"
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs fluentd
    exit 1
fi

echo "------------------------------------------"
echo "✅✅✅ All centralized logging verification tests passed."
exit 0 # Trap will cleanup.

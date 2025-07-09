#!/bin/bash
set -e

APP_MAIN_GO="./resources/app/main.go"
APP_GO_MOD="./resources/app/go.mod"
DOCKER_COMPOSE_YAML="./resources/docker-compose.yml" # This is the one solution modifies
VAULT_SETUP_SCRIPT="./setup_vault_secrets.sh" # Created by solution.sh

# Check 1: Ensure solution has modified/created required files
if ! grep -q "github.com/hashicorp/vault/api" "$APP_MAIN_GO"; then
    echo "❌ FAIL: Vault API client usage not found in '$APP_MAIN_GO'."
    exit 1
fi
if ! grep -q "github.com/hashicorp/vault/api" "$APP_GO_MOD"; then
    echo "❌ FAIL: Vault API dependency not found in '$APP_GO_MOD'."
    exit 1
fi
if ! grep -q "image: hashicorp/vault" "$DOCKER_COMPOSE_YAML" || ! grep -q "VAULT_ADDR=http://vault:8200" "$DOCKER_COMPOSE_YAML"; then
    echo "❌ FAIL: '$DOCKER_COMPOSE_YAML' does not seem to be configured correctly for Vault service or app's VAULT_ADDR."
    exit 1
fi
if [ ! -f "$VAULT_SETUP_SCRIPT" ]; then
    echo "❌ FAIL: Vault setup script '$VAULT_SETUP_SCRIPT' not found. Run solution.sh first."
    exit 1
fi
chmod +x "$VAULT_SETUP_SCRIPT"
echo "✅ PASS: Required files appear to be modified/created correctly by the solution."

# Cleanup function
cleanup() {
  echo "INFO: Cleaning up Docker environment..."
  # Use the docker-compose.yml that solution.sh modified
  docker-compose -f "$DOCKER_COMPOSE_YAML" down --remove-orphans --volumes >/dev/null 2>&1 || true # Remove volumes to clear Vault dev data
}
# Ensure cleanup happens on script exit
# However, if docker-compose up fails, the trap might run before containers are fully up for `down` command.
# So, call cleanup explicitly at end or in error paths too.
# trap cleanup EXIT # Disabled trap to allow more granular cleanup call.

# Step 2: Start services using Docker Compose
echo "INFO: Building and starting services with 'docker-compose -f $DOCKER_COMPOSE_YAML up -d --build'..."
if ! docker-compose -f "$DOCKER_COMPOSE_YAML" up -d --build; then
    echo "❌ FAIL: 'docker-compose up' failed."
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs app
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs vault
    cleanup
    exit 1
fi
echo "INFO: Services started. Waiting a bit for Vault and App to initialize (20 seconds)..."
sleep 20 # Give ample time for Vault to initialize and app to start

# Step 3: Run the Vault setup script to write secrets
echo "INFO: Running '$VAULT_SETUP_SCRIPT' to write secrets to Vault..."
if ! ./"$VAULT_SETUP_SCRIPT"; then # Source it or execute it directly
    echo "❌ FAIL: '$VAULT_SETUP_SCRIPT' failed."
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs vault
    cleanup
    exit 1
fi
echo "✅ PASS: Vault setup script completed successfully."
echo "INFO: Waiting a moment for app to potentially pick up secrets if it retries (5s)..."
sleep 5


# Step 4: Check app's /config endpoint for Vault-sourced secrets
echo "INFO: Checking app's /config endpoint..."
CONFIG_RESPONSE=$(curl -s http://localhost:8080/config)

EXPECTED_DB_PASS_OUTPUT_SUBSTRING="DB Password (from Vault): superse" # Masked: supersecretpassword123
EXPECTED_API_KEY_OUTPUT_SUBSTRING="API Key (from Vault): vaults"   # Masked: vaultsourcedapikey789
EXPECTED_SOURCE_OUTPUT_SUBSTRING="Source: Vault"

# Check if the response contains the expected substrings
PASS_FLAG=true
if echo "$CONFIG_RESPONSE" | grep -q "$EXPECTED_SOURCE_OUTPUT_SUBSTRING"; then
    echo "✅ PASS: Config source is 'Vault'."
else
    echo "❌ FAIL: Config source is not 'Vault'. Response:"
    echo "$CONFIG_RESPONSE"
    PASS_FLAG=false
fi

if echo "$CONFIG_RESPONSE" | grep -q "$EXPECTED_DB_PASS_OUTPUT_SUBSTRING"; then
    echo "✅ PASS: DB Password seems to be sourced from Vault and matches expected (masked)."
else
    echo "❌ FAIL: DB Password from /config does not match expected Vault secret (masked)."
    echo "Expected to contain: '$EXPECTED_DB_PASS_OUTPUT_SUBSTRING'"
    echo "Full Response:"
    echo "$CONFIG_RESPONSE"
    PASS_FLAG=false
fi

if echo "$CONFIG_RESPONSE" | grep -q "$EXPECTED_API_KEY_OUTPUT_SUBSTRING"; then
    echo "✅ PASS: API Key seems to be sourced from Vault and matches expected (masked)."
else
    echo "❌ FAIL: API Key from /config does not match expected Vault secret (masked)."
    echo "Expected to contain: '$EXPECTED_API_KEY_OUTPUT_SUBSTRING'"
    echo "Full Response:"
    echo "$CONFIG_RESPONSE"
    PASS_FLAG=false
fi

# Check app logs to see if it reported successful Vault connection
APP_LOGS=$(docker-compose -f "$DOCKER_COMPOSE_YAML" logs app 2>&1)
if echo "$APP_LOGS" | grep -q "Successfully fetched secrets from Vault"; then
    echo "✅ PASS: App logs indicate successful fetch from Vault."
elif echo "$APP_LOGS" | grep -q "WARN: Failed to load config from Vault"; then
    echo "❌ FAIL: App logs indicate FAILED to load config from Vault. Check Vault setup and app logic."
    echo "$APP_LOGS" # Print logs for debugging
    PASS_FLAG=false
else
    echo "❌ WARN: Could not determine Vault fetch status from app logs. Check logs manually."
    # This might not be a hard fail if /config endpoint is correct, but it's suspicious.
fi


if [ "$PASS_FLAG" = false ]; then
    echo "One or more checks failed for Vault integration."
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs app # Show app logs on failure
    docker-compose -f "$DOCKER_COMPOSE_YAML" logs vault # Show vault logs on failure
    cleanup
    exit 1
fi

echo "------------------------------------------"
echo "✅✅✅ All Vault integration verification tests passed."
cleanup
exit 0

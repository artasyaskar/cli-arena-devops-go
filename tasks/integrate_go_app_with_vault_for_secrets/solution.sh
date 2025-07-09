#!/usr/bin/env bash
set -e

APP_MAIN_GO="./resources/app/main.go"
APP_GO_MOD="./resources/app/go.mod"
DOCKER_COMPOSE_YAML="./resources/docker-compose.yml"

echo "INFO: Starting solution for integrating Go app with HashiCorp Vault..."

# Step 1: Modify app/main.go to use Vault
echo "INFO: Modifying $APP_MAIN_GO to implement Vault secret fetching..."
# This is a complex modification. We'll replace the whole file with the solution version.
cat << 'EOF_APP_MAIN_GO' > "$APP_MAIN_GO"
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strings" // For masking secrets

	"github.com/hashicorp/vault/api"
)

// AppConfig holds application configuration
type AppConfig struct {
	DBPassword string
	APIKey     string
	Source     string // "env" or "vault"
}

var appConfig AppConfig

// loadConfigFromEnv tries to load configuration from environment variables
func loadConfigFromEnv() AppConfig {
	dbPass := os.Getenv("DB_PASSWORD")
	apiKey := os.Getenv("API_KEY")

	if dbPass == "" {
		dbPass = "default_db_password_from_env" // Fallback if not set
	}
	if apiKey == "" {
		apiKey = "default_api_key_from_env" // Fallback if not set
	}
	return AppConfig{DBPassword: dbPass, APIKey: apiKey, Source: "environment variables"}
}

// loadConfigFromVault implements fetching secrets from Vault
func loadConfigFromVault() (AppConfig, error) {
	vaultAddr := os.Getenv("VAULT_ADDR")
	vaultToken := os.Getenv("VAULT_TOKEN")

	if vaultAddr == "" {
		return AppConfig{}, fmt.Errorf("VAULT_ADDR not set; cannot connect to Vault")
	}
	// Vault token can be optional if using other auth methods, but for this task, it's required.
	if vaultToken == "" {
		return AppConfig{}, fmt.Errorf("VAULT_TOKEN not set; cannot authenticate to Vault")
	}


	config := api.DefaultConfig()
	config.Address = vaultAddr

	client, err := api.NewClient(config)
	if err != nil {
		return AppConfig{}, fmt.Errorf("failed to create vault client: %w", err)
	}
	client.SetToken(vaultToken)

	secretPath := "secret/data/app/config" // KV v2 path
	log.Printf("Fetching secrets from Vault at path: %s using VAULT_ADDR: %s", secretPath, vaultAddr)
	secret, err := client.Logical().Read(secretPath)
	if err != nil {
		return AppConfig{}, fmt.Errorf("failed to read secret from vault (%s): %w", secretPath, err)
	}
	if secret == nil { // Check if secret is nil (path does not exist or no permission)
		return AppConfig{}, fmt.Errorf("no secret found at path %s in vault (secret is nil)", secretPath)
	}
    if secret.Data == nil { // Check if Data map is nil (e.g. if path was for KVv1 but read as KVv2 or vice-versa)
        log.Printf("WARN: Secret at path %s has nil Data. Raw secret: %+v", secretPath, secret)
        return AppConfig{}, fmt.Errorf("secret.Data is nil at path %s in vault", secretPath)
    }


	// For KV v2, actual data is nested under "data" key within secret.Data
	data, ok := secret.Data["data"].(map[string]interface{})
	if !ok {
		log.Printf("WARN: Could not find 'data' sub-map in Vault response for KVv2 path %s. Response: %+v", secretPath, secret.Data)
		// Attempt to read as if KVv1 or flat structure for robustness, though task specifies KVv2
		dbPass, dbOk := secret.Data["DB_PASSWORD"].(string)
		apiKey, apiOk := secret.Data["API_KEY"].(string)
		if !dbOk || !apiOk {
			return AppConfig{}, fmt.Errorf("DB_PASSWORD or API_KEY not found or not strings in Vault secret (path: %s, data: %+v, tried direct read)", secretPath, secret.Data)
		}
		log.Println("Successfully fetched secrets from Vault (using direct/KVv1 style read).")
		return AppConfig{DBPassword: dbPass, APIKey: apiKey, Source: "Vault (KVv1 style)"}, nil
	}

	dbPass, dbOk := data["DB_PASSWORD"].(string)
	apiKey, apiOk := data["API_KEY"].(string)

	if !dbOk || !apiOk {
		return AppConfig{}, fmt.Errorf("DB_PASSWORD or API_KEY not found or not strings in Vault KVv2 secret data (path: %s, data map: %+v)", secretPath, data)
	}

	log.Println("Successfully fetched secrets from Vault (KVv2 style).")
	return AppConfig{DBPassword: dbPass, APIKey: apiKey, Source: "Vault"}, nil
}

func main() {
	// Attempt to load from Vault first, fallback to environment variables
	log.Println("Attempting to load configuration...")
	cfg, err := loadConfigFromVault()
	if err != nil {
		log.Printf("WARN: Failed to load config from Vault: %s. Falling back to environment variables.", err)
		appConfig = loadConfigFromEnv()
	} else {
		appConfig = cfg
	}
	log.Printf("Application configured to use secrets from: %s", appConfig.Source)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello! App is running using secrets from %s.\n", appConfig.Source)
		fmt.Fprintf(w, "Visit /config to see (masked) configuration.\n")
	})

	http.HandleFunc("/config", func(w http.ResponseWriter, r *http.Request) {
		// Mask secrets for display
		maskedDBPass := appConfig.DBPassword
		if len(maskedDBPass) > 3 {
			maskedDBPass = maskedDBPass[:3] + strings.Repeat("*", len(maskedDBPass)-3)
		} else {
			maskedDBPass = strings.Repeat("*", len(maskedDBPass))
		}
		
		maskedAPIKey := appConfig.APIKey
		if len(maskedAPIKey) > 3 {
			maskedAPIKey = maskedAPIKey[:3] + strings.Repeat("*", len(maskedAPIKey)-3)
		} else {
			maskedAPIKey = strings.Repeat("*", len(maskedAPIKey))
		}


		fmt.Fprintf(w, "Application Configuration:\n")
		fmt.Fprintf(w, "Source: %s\n", appConfig.Source)
		fmt.Fprintf(w, "DB Password (from %s): %s\n", appConfig.Source, maskedDBPass) // Clarify source in output
		fmt.Fprintf(w, "API Key (from %s): %s\n", appConfig.Source, maskedAPIKey)     // Clarify source in output
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server starting on port %s, using secrets from %s", port, appConfig.Source)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
EOF_APP_MAIN_GO
echo "INFO: $APP_MAIN_GO updated."

# Step 2: Modify app/go.mod to include Vault client library
echo "INFO: Modifying $APP_GO_MOD to add Vault dependency..."
# Add the require line if not already present. This is a simplified way.
# A more robust way would be to use `go get github.com/hashicorp/vault/api` if Go is available.
if ! grep -q "github.com/hashicorp/vault/api" "$APP_GO_MOD"; then
  # Add require statement. Exact version might need adjustment based on Go version or latest stable.
  # Using a known compatible version. For Go 1.20, vault/api v1.9.0 or higher should be fine.
  # Let's use a version around mid-2023 for stability.
  echo -e "\nrequire github.com/hashicorp/vault/api v1.10.0" >> "$APP_GO_MOD"
  echo "INFO: Added Vault API dependency to $APP_GO_MOD. You might need to run 'go mod tidy' in the app directory if building locally."
else
  echo "INFO: Vault API dependency already present in $APP_GO_MOD."
fi
# Note: `go mod tidy` would ideally be run inside the Docker build, or by the user if testing locally.
# The Dockerfile's `RUN go mod download` should handle fetching it.

# Step 3: Modify docker-compose.yml
echo "INFO: Modifying $DOCKER_COMPOSE_YAML to include Vault service and configure app..."
cat << 'EOF_DOCKER_COMPOSE' > "$DOCKER_COMPOSE_YAML"
version: '3.8'

services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile
    container_name: go_vault_app
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      # VAULT_ADDR and VAULT_TOKEN are now primary. App should ignore these if Vault is source.
      - DB_PASSWORD=env_db_password_fallback_only 
      - API_KEY=env_api_key_fallback_only
      - VAULT_ADDR=http://vault:8200
      - VAULT_TOKEN=roottoken # Using dev root token for simplicity
    depends_on:
      - vault
    networks:
      - vault_net

  vault:
    image: hashicorp/vault:1.15 # Using a recent, specific version
    container_name: vault_server
    ports:
      - "8200:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=roottoken
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    cap_add:
      - IPC_LOCK # Required for Vault
    command: server -dev # Explicitly run in dev mode
    networks:
      - vault_net

networks:
  vault_net:
    driver: bridge
EOF_DOCKER_COMPOSE
echo "INFO: $DOCKER_COMPOSE_YAML updated."

# Step 4: Provide commands to write secrets to Vault (to be run after Vault container is up)
# These commands are for the user/agent to execute, typically using `docker exec vault_server vault ...`
# Or, they can be part of an init script for the Vault container if using a custom entrypoint.
echo "INFO: Vault setup commands (run these after 'docker-compose up -d' and Vault is ready):"
cat << EOF_VAULT_SETUP_CMDS
# Wait for Vault to be ready (approx 5-10 seconds after container starts)
# Then execute these commands, e.g., via 'docker exec vault_server sh -c "..."' or by logging into the container.
# Ensure VAULT_ADDR and VAULT_TOKEN are set in the exec environment if needed, or use the container's internal setup.

# Inside Vault container, VAULT_TOKEN is already set to roottoken by VAULT_DEV_ROOT_TOKEN_ID.
# VAULT_ADDR will default to http://127.0.0.1:8200 inside the container.

# 1. Enable KV v2 secrets engine at path 'secret/' (if not already enabled by dev mode default)
#    Dev mode usually enables a kv-v2 at secret/ by default. This is just for clarity.
#    vault secrets enable -path=secret kv-v2

# 2. Write secrets to Vault at path 'secret/data/app/config'
#    (For KVv2, the path for `kv put` includes `data` between mount and actual path)
#    vault kv put secret/app/config DB_PASSWORD="supersecretpassword123" API_KEY="vaultsourcedapikey789"

# Example using docker exec from host:
# docker exec vault_server vault login roottoken
# docker exec vault_server vault secrets enable -path=secret kv-v2  # Might say already enabled
# docker exec vault_server vault kv put secret/app/config DB_PASSWORD="supersecretpassword123" API_KEY="vaultsourcedapikey789"

# For verify.sh, these commands will be run directly.
EOF_VAULT_SETUP_CMDS

# Create a helper script for setting up Vault secrets, to be used by verify.sh or user.
# This script will be run from the host, using `docker exec`.
VAULT_SETUP_SCRIPT_PATH="./setup_vault_secrets.sh"
echo "INFO: Creating helper script '$VAULT_SETUP_SCRIPT_PATH' to write secrets to Vault..."
cat << 'EOF_VAULT_HELPER' > "$VAULT_SETUP_SCRIPT_PATH"
#!/usr/bin/env bash
set -e
VAULT_CONTAINER_NAME="vault_server" # Must match docker-compose.yml

echo "Waiting for Vault server to be ready..."
# Simple readiness check: try to read health status until it's initialized
# Timeout after 30 seconds
count=0
while true; do
    # Query Vault health, check for initialized and unsealed status
    # The `- ተ` part of the grep is to handle potential color codes in output if TTY is detected.
    # A more robust check might use jq on the JSON output.
    health_status=$(docker exec "$VAULT_CONTAINER_NAME" vault status -format=json 2>/dev/null || echo "{}")
    initialized=$(echo "$health_status" | jq -r .initialized)
    sealed=$(echo "$health_status" | jq -r .sealed)

    if [ "$initialized" == "true" ] && [ "$sealed" == "false" ]; then
        echo "Vault is initialized and unsealed."
        break
    fi

    count=$((count + 1))
    if [ "$count" -ge 15 ]; then # Approx 30 seconds (15 * 2s)
        echo "ERROR: Vault did not become ready in time."
        echo "Last health status: $health_status"
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""


echo "Logging into Vault (already logged in as root in dev mode, but good practice for CLI)..."
# docker exec "$VAULT_CONTAINER_NAME" vault login -no-print roottoken
# No need to login if VAULT_TOKEN is passed or if using root token in dev server.

echo "Enabling KV v2 secrets engine at path 'secret/' (if not already enabled)..."
# This might return an error if already enabled, so ignore error with `|| true`
docker exec "$VAULT_CONTAINER_NAME" vault secrets enable -path=secret kv-v2 || echo "INFO: KV v2 engine at 'secret/' might already be enabled."

echo "Writing secrets to Vault at 'secret/app/config' (KVv2 path for CLI is 'secret/app/config')..."
# Note: For `vault kv put secret/foo`, if 'secret' is a KVv2 mount, it writes to `secret/data/foo`.
docker exec "$VAULT_CONTAINER_NAME" vault kv put secret/app/config \
    DB_PASSWORD="supersecretpassword123" \
    API_KEY="vaultsourcedapikey789"

echo "Secrets written to Vault."
echo "  DB_PASSWORD=supersecretpassword123"
echo "  API_KEY=vaultsourcedapikey789"
echo "  at path secret/app/config (which means secret/data/app/config for KVv2 API reads)"
exit 0
EOF_VAULT_HELPER
chmod +x "$VAULT_SETUP_SCRIPT_PATH"

echo "INFO: Solution script finished."
echo "To run: "
echo "  1. docker-compose -f $DOCKER_COMPOSE_YAML up -d --build"
echo "  2. ./$VAULT_SETUP_SCRIPT_PATH"
echo "  3. Access app at http://localhost:8080, check /config endpoint."
echo "To stop: docker-compose -f $DOCKER_COMPOSE_YAML down"

exit 0

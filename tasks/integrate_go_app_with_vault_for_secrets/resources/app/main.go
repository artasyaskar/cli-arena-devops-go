package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	// Vault client will be added by the user/agent
	// "github.com/hashicorp/vault/api"
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

// loadConfigFromVault will be implemented by the user/agent
/*
func loadConfigFromVault() (AppConfig, error) {
	vaultAddr := os.Getenv("VAULT_ADDR")   // e.g., "http://vault:8200"
	vaultToken := os.Getenv("VAULT_TOKEN") // e.g., "roottoken"

	if vaultAddr == "" || vaultToken == "" {
		return AppConfig{}, fmt.Errorf("VAULT_ADDR or VAULT_TOKEN not set")
	}

	config := api.DefaultConfig()
	config.Address = vaultAddr

	client, err := api.NewClient(config)
	if err != nil {
		return AppConfig{}, fmt.Errorf("failed to create vault client: %w", err)
	}
	client.SetToken(vaultToken)

	// Path to secrets: secret/data/app/config for KV v2
	// For KV v1, it would be secret/app/config
	secretPath := "secret/data/app/config"
	log.Printf("Fetching secrets from Vault at path: %s", secretPath)
	secret, err := client.Logical().Read(secretPath)
	if err != nil {
		return AppConfig{}, fmt.Errorf("failed to read secret from vault (%s): %w", secretPath, err)
	}
	if secret == nil || secret.Data == nil {
		return AppConfig{}, fmt.Errorf("no data found at secret path %s in vault", secretPath)
	}

    // For KV v2, actual data is nested under "data"
    data, ok := secret.Data["data"].(map[string]interface{})
    if !ok {
        // Maybe it's KV v1, or data is not in expected format
        log.Printf("WARN: Secret data from Vault at %s is not in KVv2 'data' sub-map. Trying to read directly.", secretPath)
        // Try reading as if KVv1 or flat structure
        dbPass, dbOk := secret.Data["DB_PASSWORD"].(string)
        apiKey, apiOk := secret.Data["API_KEY"].(string)
        if !dbOk || !apiOk {
             return AppConfig{}, fmt.Errorf("DB_PASSWORD or API_KEY not found or not strings in Vault secret data: %+v", secret.Data)
        }
        return AppConfig{DBPassword: dbPass, APIKey: apiKey, Source: "Vault (attempted direct read)"}, nil
    }


	dbPass, dbOk := data["DB_PASSWORD"].(string)
	apiKey, apiOk := data["API_KEY"].(string)

	if !dbOk || !apiOk {
		return AppConfig{}, fmt.Errorf("DB_PASSWORD or API_KEY not found or not strings in Vault secret (path: %s, data: %+v)", secretPath, data)
	}

	log.Println("Successfully fetched secrets from Vault.")
	return AppConfig{DBPassword: dbPass, APIKey: apiKey, Source: "Vault"}, nil
}
*/

func main() {
	// Attempt to load from Vault first, fallback to environment variables
	// User/agent needs to implement loadConfigFromVault and uncomment the logic below.
	/*
		cfg, err := loadConfigFromVault()
		if err != nil {
			log.Printf("WARN: Failed to load config from Vault: %v. Falling back to environment variables.", err)
			appConfig = loadConfigFromEnv()
		} else {
			appConfig = cfg
		}
	*/
	// Initial state: always load from environment variables
	appConfig = loadConfigFromEnv()
	log.Printf("Application configured to use secrets from: %s", appConfig.Source)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello! App is running using secrets from %s.\n", appConfig.Source)
		fmt.Fprintf(w, "Visit /config to see (masked) configuration.\n")
	})

	http.HandleFunc("/config", func(w http.ResponseWriter, r *http.Request) {
		// Mask secrets for display
		maskedDBPass := appConfig.DBPassword
		if len(maskedDBPass) > 4 {
			maskedDBPass = maskedDBPass[:4] + "..."
		}
		maskedAPIKey := appConfig.APIKey
		if len(maskedAPIKey) > 4 {
			maskedAPIKey = maskedAPIKey[:4] + "..."
		}

		fmt.Fprintf(w, "Application Configuration:\n")
		fmt.Fprintf(w, "Source: %s\n", appConfig.Source)
		fmt.Fprintf(w, "DB Password: %s\n", maskedDBPass)
		fmt.Fprintf(w, "API Key: %s\n", maskedAPIKey)
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

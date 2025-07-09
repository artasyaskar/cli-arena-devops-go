package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func handler(w http.ResponseWriter, r *http.Request) {
	apiKey := os.Getenv("API_KEY")
	if apiKey == "" {
		apiKey = "NOT_SET"
	}
	// Simulate checking API_KEY usage for task verification, not a real security check for the key's value
	if r.URL.Path == "/check_api_key_usage" {
		if apiKey != "NOT_SET" && apiKey != "dummy_value_replace_me_in_production" {
			fmt.Fprintf(w, "API_KEY is configured for use by the application.\n")
			return
		}
		fmt.Fprintf(w, "API_KEY is either not set or still the placeholder value.\n")
		return
	}

	log.Printf("Received request for %s from %s\n", r.URL.Path, r.RemoteAddr)
	fmt.Fprintf(w, "Hello from the Go web server!\n")
	fmt.Fprintf(w, "API_KEY: %s\n", apiKey)
	fmt.Fprintf(w, "User: %s\n", os.Getenv("APP_USER")) // For checking non-root user
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Healthy\n")
}

func main() {
	http.HandleFunc("/", handler)
	http.HandleFunc("/health", healthHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server starting on port %s\n", port)
	log.Printf("Attempting to run as user: %s (UID: %d, GID: %d)\n", os.Getenv("APP_USER"), os.Getuid(), os.Getgid())

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

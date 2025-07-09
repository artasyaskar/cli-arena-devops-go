package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func helloHandler(w http.ResponseWriter, r *http.Request) { // Renamed function to helloHandler
	log.Printf("Received request from %s: %s %s", r.RemoteAddr, r.Method, r.URL.Path)
	// Respond with a simple JSON containing request headers
	w.Header().Set("Content-Type", "application/json")
	// For simplicity, let's just echo back the User-Agent header in a JSON structure
	// In a real reverse proxy, you'd copy many headers and the body.
	userAgent := r.Header.Get("User-Agent")
	responseJSON := fmt.Sprintf(`{"message": "Hello from placeholder!", "user_agent": "%s"}`, userAgent)
	if _, err := fmt.Fprint(w, responseJSON); err != nil {
		log.Printf("Error writing response: %v", err)
		http.Error(w, "Failed to write response", http.StatusInternalServerError)
	}
}

func main() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080" // Default port if not specified
	}

	http.HandleFunc("/", helloHandler) // Renamed handler to helloHandler
	log.Printf("Placeholder Go app listening on port %s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %s", err)
	}
}

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
)

func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Log all headers to stdout for debugging/verification
	fmt.Println("Received request for:", r.URL.String())
	fmt.Println("Headers:")
	headersMap := make(map[string][]string)
	for name, values := range r.Header {
		fmt.Printf("  %s: %v\n", name, values)
		headersMap[name] = values
	}

	// Respond with the received headers as JSON
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(headersMap); err != nil {
		log.Printf("Error encoding headers to JSON: %v", err)
		http.Error(w, "Failed to encode headers", http.StatusInternalServerError)
	}
}

func main() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080" // Default port
	}

	http.HandleFunc("/", helloHandler)

	log.Printf("Go app server starting on port %s\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

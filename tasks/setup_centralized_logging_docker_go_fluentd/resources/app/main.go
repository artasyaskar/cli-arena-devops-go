package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

// User will modify this to use a structured JSON logger.
// For now, using standard log package.

func handler(w http.ResponseWriter, r *http.Request) {
	log.Printf("INFO: Received request for %s from %s", r.URL.Path, r.RemoteAddr) // Standard log
	fmt.Fprintf(w, "Hello from the Go logging app!\n")
	// Simulate an error log
	if r.URL.Path == "/error" {
		log.Printf("ERROR: This is a simulated error event triggered by accessing /error.") // Standard log
		fmt.Fprintf(w, "Error event logged.\n")
		return
	}
	// Simulate a message to be skipped
	if r.URL.Path == "/skip" {
		log.Printf("INFO: This is a special skip_this_log_message for testing filters.") // Standard log
		fmt.Fprintf(w, "Skip message logged (should be filtered by Fluentd).\n")
		return
	}
}

func main() {
	// Initial log to indicate service name (user should incorporate this into JSON logs)
	log.Println("INFO: Starting Go application (service_name: go-app)") // Standard log

	http.HandleFunc("/", handler)
	http.HandleFunc("/error", handler) // Route to trigger error log
	http.HandleFunc("/skip", handler)  // Route to trigger skippable log

	// Periodically log a heartbeat message
	go func() {
		for {
			time.Sleep(30 * time.Second)
			log.Println("INFO: Application heartbeat.") // Standard log
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("INFO: Server starting on port %s", port) // Standard log
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("FATAL: Failed to start server: %v", err) // Standard log, but fatal
	}
}

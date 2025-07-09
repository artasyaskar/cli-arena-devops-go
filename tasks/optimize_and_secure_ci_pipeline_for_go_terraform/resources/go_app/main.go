package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"
)

var (
	counter int
	mu      sync.Mutex // For demonstrating -race flag if not handled correctly
)

// Potentially problematic function for race detector if not locked
func incrementCounter() {
	// mu.Lock() // Uncomment to fix race condition
	temp := counter
	time.Sleep(time.Millisecond) // Yield to increase chance of race
	temp++
	counter = temp
	// mu.Unlock() // Uncomment to fix race condition
}

func handler(w http.ResponseWriter, r *http.Request) {
	// Simulate some work and logging
	log.Printf("Handling request for %s from %s", r.URL.Path, r.RemoteAddr)

	// Call the potentially racy function
	go incrementCounter() // Run in a goroutine to make race more likely if not locked
	go incrementCounter() // Run another one

	fmt.Fprintf(w, "Hello from the Go CI App! Counter (may be racy): %d\n", counter)
}

// A simple function to test
func Add(a, b int) int {
	return a + b
}

// A function with a deliberate (but trivial) security issue for gosec to find
func vulnerableFunction(userInput string) {
	// Example: SQL injection (conceptual, as we don't have a DB)
	query := "SELECT * FROM users WHERE name = '" + userInput + "'"
	log.Printf("Executing query (conceptually): %s", query) // G402: Look for SQL injection. gosec should flag this.

	// Example: Command injection (conceptual)
	// cmd := exec.Command("sh", "-c", "echo "+userInput) // G204: Subprocess launched with variable
	// cmd.Run()
}

func main() {
	log.Println("Starting Go CI App...")
	http.HandleFunc("/", handler)

	// For gosec testing
	vulnerableFunction("test_user_input")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Server listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %s", err)
	}
}

package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("Request from %s for %s", r.RemoteAddr, r.URL.Path)
		fmt.Fprintln(w, "Hello from a Go app!")
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("Health check from %s", r.RemoteAddr)
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "Healthy")
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	uid := os.Getuid()
	gid := os.Getgid()
	username := os.Getenv("USER")
	if username == "" {
		username = "unknown" // Fallback if USER env var not set
	}


	log.Printf("Server starting on port %s", port)
	log.Printf("Running as User: %s (UID: %d, GID: %d)", username, uid, gid)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

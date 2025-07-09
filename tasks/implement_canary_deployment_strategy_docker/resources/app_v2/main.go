package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("v2: Received request for %s from %s", r.URL.Path, r.RemoteAddr)
		fmt.Fprintf(w, "Hello from App version v2 (Canary)!\n")
	})

	http.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("v2: Received request for /version from %s", r.RemoteAddr)
		fmt.Fprintf(w, "App version v2")
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082" // v2 listens on 8082
	}
	log.Printf("App v2 (Canary) starting on port %s\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

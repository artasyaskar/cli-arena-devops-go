package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("v1: Received request for %s from %s", r.URL.Path, r.RemoteAddr)
		fmt.Fprintf(w, "Hello from App version v1!\n")
	})

	http.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("v1: Received request for /version from %s", r.RemoteAddr)
		fmt.Fprintf(w, "App version v1")
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081" // v1 listens on 8081
	}
	log.Printf("App v1 starting on port %s\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

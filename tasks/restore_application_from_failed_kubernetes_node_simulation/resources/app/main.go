package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
)

const dataFile = "/data/store.json" // Path inside the container, mapped to a volume

var (
	store = make(map[string]string)
	mu    sync.RWMutex
)

func loadData() {
	mu.Lock()
	defer mu.Unlock()

	// Ensure directory exists
	dataDir := filepath.Dir(dataFile)
	if _, err := os.Stat(dataDir); os.IsNotExist(err) {
		log.Printf("Data directory %s does not exist, creating...", dataDir)
		if err := os.MkdirAll(dataDir, 0755); err != nil {
			log.Printf("WARN: Could not create data directory %s: %v. Starting with empty store.", dataDir, err)
			store = make(map[string]string) // Initialize if dir creation fails
			return
		}
	}


	data, err := ioutil.ReadFile(dataFile)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Data file %s not found. Starting with an empty store.", dataFile)
			store = make(map[string]string) // Initialize if file doesn't exist
			return
		}
		log.Printf("WARN: Error reading data file %s: %v. Starting with empty store.", dataFile, err)
		store = make(map[string]string) // Initialize on other read errors too
		return
	}

	if len(data) == 0 { // Handle empty file case
		log.Printf("Data file %s is empty. Starting with an empty store.", dataFile)
		store = make(map[string]string)
		return
	}

	err = json.Unmarshal(data, &store)
	if err != nil {
		log.Printf("WARN: Error unmarshaling data from %s: %v. Data might be corrupted. Starting with empty store.", dataFile, err)
		// If data is corrupted, start fresh to avoid app crash or inconsistent state.
		store = make(map[string]string)
		return
	}
	log.Printf("Successfully loaded %d key-value pairs from %s.", len(store), dataFile)
}

func saveData() error {
	mu.RLock() // Use RLock for reading the store map, but need full Lock for file write
	defer mu.RUnlock()

	// Re-acquire full lock for the critical section of marshaling and writing
	// This is a bit simplified; a full lock around the whole operation might be safer if store is large
	// or if other writes could happen to the file system.
	// For this example, the RLock then full Lock pattern is illustrative.
	// A better pattern: mu.Lock() at start, mu.Unlock() at end of saveData.
	// Let's use a full lock for the whole save operation for safety.
	// So, this function should be called when mu is already Write-Locked or acquire it.
	// The current call pattern in setHandler does this.

	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return fmt.Errorf("error marshaling data: %w", err)
	}

	// Ensure directory exists before writing (important for first write or after volume recreation)
	dataDir := filepath.Dir(dataFile)
	if _, err := os.Stat(dataDir); os.IsNotExist(err) {
		if err := os.MkdirAll(dataDir, 0755); err != nil {
			return fmt.Errorf("could not create data directory %s before saving: %w", dataDir, err)
		}
	}


	err = ioutil.WriteFile(dataFile, data, 0644)
	if err != nil {
		return fmt.Errorf("error writing data file %s: %w", dataFile, err)
	}
	log.Printf("Data saved to %s (%d items).", dataFile, len(store))
	return nil
}

func setHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed for /set", http.StatusMethodNotAllowed)
		return
	}
	key := r.URL.Query().Get("key")
	value := r.URL.Query().Get("value")

	if key == "" {
		http.Error(w, "Missing 'key' query parameter", http.StatusBadRequest)
		return
	}

	mu.Lock()
	store[key] = value
	err := saveData()
	mu.Unlock()

	if err != nil {
		log.Printf("ERROR: Failed to save data after setting key '%s': %v", key, err)
		http.Error(w, fmt.Sprintf("Failed to save data: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("Set key='%s', value='%s'", key, value)
	fmt.Fprintf(w, "Set: %s = %s\n", key, value)
}

func getHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Only GET method is allowed for /get", http.StatusMethodNotAllowed)
		return
	}
	key := r.URL.Query().Get("key")
	if key == "" {
		http.Error(w, "Missing 'key' query parameter", http.StatusBadRequest)
		return
	}

	mu.RLock()
	value, ok := store[key]
	mu.RUnlock()

	if !ok {
		log.Printf("Key not found: '%s'", key)
		http.Error(w, fmt.Sprintf("Key not found: %s", key), http.StatusNotFound)
		return
	}

	log.Printf("Get key='%s', value='%s'", key, value)
	fmt.Fprintf(w, "%s\n", value)
}

func listHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Only GET method is allowed for /list", http.StatusMethodNotAllowed)
		return
	}
	mu.RLock()
	dataCopy := make(map[string]string)
	for k, v := range store {
		dataCopy[k] = v
	}
	mu.RUnlock()

	jsonData, err := json.MarshalIndent(dataCopy, "", "  ")
	if err != nil {
		http.Error(w, "Failed to marshal data to JSON", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(jsonData)
	log.Printf("Listed %d items.", len(dataCopy))
}


func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds) // More precise logs
	log.Println("INFO: Stateful Go application starting...")
	loadData() // Load existing data on startup

	http.HandleFunc("/set", setHandler)
	http.HandleFunc("/get", getHandler)
	http.HandleFunc("/list", listHandler) // Endpoint to view all data

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("INFO: Server listening on port %s. Data file: %s", port, dataFile)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("FATAL: Failed to start server: %v", err)
	}
}

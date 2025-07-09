#!/usr/bin/env bash
set -e

APP_MAIN_GO="./resources/app/main.go"
APP_GO_MOD="./resources/app/go.mod"
APP_DOCKERFILE="./resources/app/Dockerfile" # May need minor tweaks for go mod
FLUENT_CONF="./resources/fluentd/fluent.conf"
DOCKER_COMPOSE_YAML="./resources/docker-compose.yml"

echo "INFO: Starting solution for setting up centralized logging with Fluentd."

# Step 1: Modify app/main.go for structured JSON logging
echo "INFO: Modifying $APP_MAIN_GO for structured JSON logging..."
# Using standard library "encoding/json" for simplicity. Zerolog would be more robust.
cat << 'EOF_APP_MAIN_GO' > "$APP_MAIN_GO"
package main

import (
	"encoding/json"
	"fmt"
	"log"      // Standard log for initial messages or if JSON fails
	"net/http"
	"os"
	"time"
)

const serviceName = "go-app"

// LogEntry defines the structure for JSON logs
type LogEntry struct {
	Level       string `json:"level"`
	Timestamp   string `json:"timestamp"` // ISO8601 format
	ServiceName string `json:"service_name"`
	Message     string `json:"message"`
	// Additional fields can be added here
	RequestPath string `json:"request_path,omitempty"`
	RemoteAddr  string `json:"remote_addr,omitempty"`
}

// Helper to write JSON logs to stdout
func writeJSONLog(level, message string, extraFields map[string]string) {
	entry := LogEntry{
		Level:       level,
		Timestamp:   time.Now().UTC().Format(time.RFC3339Nano),
		ServiceName: serviceName,
		Message:     message,
	}

	// For simplicity, not adding extra fields directly into LogEntry struct dynamically.
	// A real implementation would merge extraFields or use a map[string]interface{} for the whole log.
	// This example will just append them to the message for now, or rely on specific log calls.

	logData, err := json.Marshal(entry)
	if err != nil {
		// Fallback to standard log if JSON marshaling fails
		log.Printf("ERROR: Failed to marshal JSON log: %v. Original log: [%s] %s", err, level, message)
		return
	}
	fmt.Println(string(logData)) // Output JSON log to stdout
}
func writeJSONLogWithContext(level, message, path, remoteAddr string) {
	entry := LogEntry{
		Level:       level,
		Timestamp:   time.Now().UTC().Format(time.RFC3339Nano),
		ServiceName: serviceName,
		Message:     message,
		RequestPath: path,
		RemoteAddr:  remoteAddr,
	}
	logData, err := json.Marshal(entry)
	if err != nil {
		log.Printf("ERROR: Failed to marshal JSON log: %v. Original log: [%s] %s", err, level, message)
		return
	}
	fmt.Println(string(logData))
}


func handler(w http.ResponseWriter, r *http.Request) {
	writeJSONLogWithContext("info", fmt.Sprintf("Received request for %s", r.URL.Path), r.URL.Path, r.RemoteAddr)
	fmt.Fprintf(w, "Hello from the Go logging app! Check Fluentd for structured logs.\n")

	if r.URL.Path == "/error" {
		writeJSONLogWithContext("error", "This is a simulated error event.", r.URL.Path, r.RemoteAddr)
		fmt.Fprintf(w, "Error event logged in JSON.\n")
		return
	}
	if r.URL.Path == "/skip" {
		writeJSONLogWithContext("info", "This is a special skip_this_log_message for testing filters.", r.URL.Path, r.RemoteAddr)
		fmt.Fprintf(w, "Skip message logged (should be filtered by Fluentd).\n")
		return
	}
}

func main() {
	// Disable standard logger's prefixes if all logs go through JSON helper
	// log.SetFlags(0) // Or redirect standard logger output if some components still use it.
	// For this task, we'll let initial std logs pass through, Fluentd might capture them differently.

	writeJSONLog("info", fmt.Sprintf("Starting Go application (service_name: %s)", serviceName), nil)

	http.HandleFunc("/", handler)
	http.HandleFunc("/error", handler)
	http.HandleFunc("/skip", handler)

	go func() {
		for {
			time.Sleep(30 * time.Second)
			writeJSONLog("info", "Application heartbeat.", nil)
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	writeJSONLog("info", fmt.Sprintf("Server starting on port %s", port), nil)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		// Use standard log for fatal error as JSON logger might not be available if ListenAndServe fails early
		log.Fatalf("FATAL: Failed to start server: %v", err)
	}
}
EOF_APP_MAIN_GO
echo "INFO: $APP_MAIN_GO updated for JSON logging."

# Step 2: Modify app/go.mod (if a library like zerolog was used, add it here)
# Since we used encoding/json, no changes to go.mod are strictly necessary for new dependencies.
# Ensure Dockerfile runs `go mod download` if go.sum exists, which it does.
echo "INFO: $APP_GO_MOD does not require changes as standard library 'encoding/json' was used."
# Ensure Dockerfile has `RUN go mod download`
if ! grep -q "RUN go mod download" "$APP_DOCKERFILE" && grep -q "COPY go.mod go.sum ./" "$APP_DOCKERFILE"; then
    sed -i '/COPY go.mod go.sum .\/$/a RUN go mod download' "$APP_DOCKERFILE"
    echo "INFO: Added 'RUN go mod download' to $APP_DOCKERFILE"
fi


# Step 3: Create/Update fluent.conf
echo "INFO: Creating $FLUENT_CONF with required Fluentd configuration..."
cat << 'EOF_FLUENT_CONF' > "$FLUENT_CONF"
# fluent.conf

# Source: Listen for logs from Docker containers using fluentd log driver
<source>
  @type forward
  port 24224
  bind 0.0.0.0
  tag_key @log_name # Use the tag provided by docker log driver options
</source>

# Filter 1: Parse the JSON log message from Docker
# Docker's fluentd log driver wraps the actual log line in a field called "log".
<filter docker.go_app.**> # Match tags starting with "docker.go_app"
  @type parser
  key_name log # Field containing the JSON string from the Go app
  reserve_data true # Keep original fields from Docker log driver (like container_id, container_name)
  remove_key_name_field true # Remove the original "log" field after parsing its content
  <parse>
    @type json
    # Fluentd tries to use 'time' field by default if present in JSON.
    # Our JSON logs have 'timestamp'. If we want Fluentd to use it as official event time:
    time_key timestamp
    time_type string # Specify that 'timestamp' is a string
    time_format %iso8601 # Corresponds to time.RFC3339Nano. Use %iso8601 for general ISO8601.
                        # For RFC3339Nano (e.g. "2023-10-27T10:20:30.123456789Z"),
                        # use: time_format %Y-%m-%dT%H:%M:%S.%NZ or %Y-%m-%dT%H:%M:%S.%L%z
                        # For simplicity, we'll let Fluentd manage its own event time if parsing 'timestamp' is tricky.
                        # Or, ensure Go app outputs a format Fluentd's default parser understands.
                        # Let's assume Go outputs standard ISO8601 like RFC3339 which Fluentd handles.
  </parse>
</filter>

# Filter 2: Enrich logs - add static field and conditional field
<filter docker.go_app.**>
  @type record_transformer
  enable_ruby true # Needed for conditional logic with ${...}
  auto_typecast true # Try to convert string numbers to numeric, etc.
  <record>
    environment "development" # Static field
    # Add 'priority: "high"' if 'level' field (from parsed JSON) is "error"
    priority ${record["level"] == "error" ? "high" : nil}
  </record>
  # Remove the 'priority' field if it was set to nil (i.e., level was not 'error')
  remove_keys ["priority"] if record["priority"].nil?
</filter>

# Filter 3: Drop logs containing "skip_this_log_message" in the 'message' field
<filter docker.go_app.**>
  @type grep
  <exclude>
    key message # Field from parsed JSON
    pattern /skip_this_log_message/
  </exclude>
</filter>

# Output: Copy logs to two destinations: a local file and a TCP forwarder
<match docker.go_app.**>
  @type copy
  # Store 1: Local file
  <store>
    @type file
    path /fluentd/log/app.log.json # Path inside Fluentd container
    append true # Append to the file
    <format>
      @type json # Write each log entry as a JSON line
    </format>
    <buffer time> # Use time-sliced buffer
      timekey 1m    # Flush every 1 minute
      timekey_wait 10s # Wait 10s for more logs before flushing slice
      chunk_limit_size 1MB # Max size of a chunk file
    </buffer>
  </store>

  # Store 2: Forward to TCP netcat listener
  <store>
    @type forward
    send_timeout 60s
    recover_wait 10s
    hard_timeout 60s
    # require_ack true # If receiver supports it, for reliability

    <server>
      name netcat_server
      host netcat_listener # Docker Compose service name for the netcat listener
      port 24225          # Port netcat_listener listens on
      # protocol tcp # default
    </server>
    <buffer> # Buffer configuration for forwarding
        @type memory # Use memory buffer
        flush_interval 1s # Flush buffer every second
        chunk_limit_size 100k # Smaller chunk size for faster forwarding of small logs
    </buffer>
  </store>
</match>

# Optional: Catch-all for logs not matched above (e.g., Fluentd internal logs)
<match **>
  @type stdout
  # Or forward to a different file/output if needed
</match>
EOF_FLUENT_CONF
echo "INFO: $FLUENT_CONF created."


# Step 4: Update docker-compose.yml
echo "INFO: Modifying $DOCKER_COMPOSE_YAML to add Fluentd, netcat_listener, and configure app logging..."
cat << 'EOF_DOCKER_COMPOSE' > "$DOCKER_COMPOSE_YAML"
version: '3.8'

services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile
    container_name: go_logging_app
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
    # Configure Docker's fluentd logging driver
    logging:
      driver: "fluentd"
      options:
        # Address of the Fluentd service (name 'fluentd' and default port 24224)
        fluentd-address: "fluentd:24224"
        # Tag for logs from this service. {{.Name}} is service name, {{.ID}} is container ID.
        tag: "docker.go_app.{{.Name}}"
        # fluentd-async: "true" # Non-blocking log delivery
        # fluentd-retry-wait: "1s"
        # fluentd-max-retries: "30"
    depends_on:
      - fluentd # Ensure fluentd is up before app tries to send logs (though driver might buffer)
    networks:
      - logging_net

  fluentd:
    image: fluent/fluentd:v1.16-debian-1 # Using a specific, recent version (debian base)
    container_name: fluentd_collector
    ports:
      - "24224:24224"       # Fluentd forward input (TCP)
      - "24224:24224/udp"   # Fluentd forward input (UDP)
    volumes:
      - ./fluentd/fluent.conf:/fluentd/etc/fluent.conf:ro # Mount custom config
      - ./fluentd_logs:/fluentd/log # Volume for Fluentd's file output
    depends_on:
      - netcat_listener # Ensure listener is available if fluentd tries to connect on startup
    networks:
      - logging_net
    # user: fluent # Good practice to run as non-root if image supports it easily.
                 # Default fluent/fluentd runs as root, then drops to fluent user for worker processes.

  netcat_listener:
    image: alpine/socat:1.7.4.4-r0 # socat is more reliable than basic netcat for services
    container_name: nc_listener
    # Listens on TCP port 24225, prints received data to stdout (visible in 'docker logs nc_listener')
    # 'fork' allows it to handle multiple connections (though Fluentd forward usually keeps one)
    # 'reuseaddr' allows quick restart
    command: tcp-listen:24225,fork,reuseaddr, લોકો stdout
    # Expose port for Fluentd to connect within the Docker network (not needed on host)
    # ports:
    #   - "24225:24225" # Only if you want to test netcat from host, not needed for fluentd->netcat
    networks:
      - logging_net

networks:
  logging_net:
    driver: bridge

volumes:
  fluentd_logs: # Define the named volume used by fluentd for its file output
    driver: local
EOF_DOCKER_COMPOSE
echo "INFO: $DOCKER_COMPOSE_YAML updated."

echo "INFO: Solution script finished."
echo "To run:"
echo "  1. (If local) Ensure ./resources/fluentd_logs directory exists or Docker will create it as root."
echo "     mkdir -p ./resources/fluentd_logs && chmod 777 ./resources/fluentd_logs"
echo "  2. docker-compose -f $DOCKER_COMPOSE_YAML up -d --build"
echo "  3. Access app at http://localhost:8080, or http://localhost:8080/error, http://localhost:8080/skip"
echo "  4. Check logs in ./resources/fluentd_logs/app.log.json (path on host depends on volume mount)"
echo "  5. Check logs from netcat: docker logs nc_listener"
echo "To stop: docker-compose -f $DOCKER_COMPOSE_YAML down -v (to remove volume)"

exit 0

#!/usr/bin/env bash
set -e

echo "INFO: Creating Dockerfile.fixed with the corrected multi-stage build."



cat << EOF > Dockerfile.fixed
# Stage 1: Builder
# Use alpine for a smaller builder stage and to ensure CGO_ENABLED=0 is important.
FROM golang:1.20-alpine AS builder

# Set WORKDIR early
WORKDIR /app

# Copy go.mod and go.sum first to leverage Docker cache for dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the application source code
COPY . .

# Build the Go application
# - CGO_ENABLED=0 for a statically linked binary, crucial for alpine scratch/distroless.
# - -ldflags="-w -s" to strip debug information and reduce binary size.
# - Output to /app/application (or any path within WORKDIR)
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/application main.go

# Stage 2: Final image
# Use a minimal base image like alpine or scratch/distroless. Alpine is simpler for this task.
FROM alpine:latest

# Create a non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set WORKDIR
WORKDIR /app

# Copy only the compiled application binary from the builder stage
# Ensure correct ownership if WORKDIR is not writable by appuser by default,
# or copy to a location like /usr/local/bin and ensure appuser can execute.
# Here, WORKDIR /app is created by root, then we copy into it.
# Chown the WORKDIR and its contents after copy, or chown the copied binary.
COPY --from=builder --chown=appuser:appgroup /app/application .

# Switch to the non-root user
USER appuser

# Expose the port the application listens on (default 8080 for this app)
EXPOSE 8080
ENV PORT=8080

# Command to run the application
CMD ["./application"]
EOF

echo "INFO: Dockerfile.fixed has been created."
echo "To build the image: docker build -f Dockerfile.fixed -t fixed-app ./resources/app"
echo "To run the container: docker run -p 8080:8080 fixed-app"

exit 0

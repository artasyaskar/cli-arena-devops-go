# Use a lighter base image for Go
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy Go modules and download dependencies first for caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY main.go .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /app/reverseproxy_server .

# --- Final stage ---
FROM alpine:latest

WORKDIR /app

# Copy the pre-built binary from the builder stage
COPY --from=builder /app/reverseproxy_server /app/reverseproxy_server

# Expose port (though NGINX will be the public entry point)
EXPOSE 8080

# Command to run the executable
CMD ["/app/reverseproxy_server"]

FROM golang:1.20-alpine AS builder
WORKDIR /app

# Copy module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy application source
COPY main.go .

# Build the application
# User might need to ensure CA certificates are available if Vault uses TLS,
# though Vault dev server uses HTTP by default.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/vault_app main.go

# Final stage
FROM alpine:latest
# Add ca-certificates in case Vault server uses TLS (even self-signed for dev)
# or if the app needs to make other HTTPS calls.
RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /app/vault_app .

# Non-root user setup
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080
ENV PORT=8080
# VAULT_ADDR and VAULT_TOKEN will be passed from docker-compose.yml

CMD ["./vault_app"]

FROM golang:1.20-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
# Handle case where go.sum might not exist initially if no deps
RUN if [ -f "go.sum" ]; then go mod download; else go mod tidy; fi


COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/stateful_app main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates

# Create /data directory and set up user/permissions
# The app writes to /data/store.json. This directory needs to exist and be writable by appuser.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup \
    && mkdir -p /data && chown appuser:appgroup /data

WORKDIR /app # Binary will be here
COPY --from=builder /app/stateful_app .
RUN chown appuser:appgroup /app/stateful_app # Ensure binary is owned by appuser

USER appuser

VOLUME /data # Declare /data as a volume mount point

EXPOSE 8080
ENV PORT=8080

CMD ["./stateful_app"]

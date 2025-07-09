FROM golang:1.20-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
# RUN go mod download # Not strictly needed if no external deps initially, but good practice.
# If user adds zerolog, `go get` or `go mod tidy` then `download` would be typical.
# For this task, `go mod download` in solution Dockerfile is better.
RUN if [ -f "go.sum" ]; then go mod download; fi


COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/logging_app main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates # Good practice, though not strictly needed for this task yet

WORKDIR /app
COPY --from=builder /app/logging_app .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080
ENV PORT=8080

CMD ["./logging_app"]

FROM golang:1.20-alpine as builder
WORKDIR /app
COPY go.mod .
COPY go.sum .
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/service_v1 main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/service_v1 .
# Add non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 8081
CMD ["/app/service_v1"]

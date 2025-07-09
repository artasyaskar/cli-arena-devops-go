# Base image for Go applications
FROM golang:1.21-alpine

# Set working directory
WORKDIR /app

# Copy Go modules and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the application code
COPY . .

# Build the Go app (if applicable, otherwise this can be adjusted)
# RUN go build -o /app/main ./src/...

# Expose port (if needed by the application)
# EXPOSE 8080

# Command to run the application (replace with actual command)
# CMD ["/app/main"]
# For now, a placeholder command
CMD ["tail", "-f", "/dev/null"]

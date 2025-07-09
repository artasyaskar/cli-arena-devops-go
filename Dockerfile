

# Use official lightweight Go image
FROM golang:1.21-alpine

# Set working directory inside container
WORKDIR /app

# Copy Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire project (adjust this if needed)
COPY . .

# Build the Go application from src/main.go
RUN go build -o cli-arena-devops-go ./src/main.go

# Expose the HTTP port your app listens on
EXPOSE 8080

# Run the compiled binary
CMD ["./cli-arena-devops-go"]

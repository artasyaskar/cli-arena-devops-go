# Use official lightweight Go image
FROM golang:1.21-alpine

# Set working directory inside container
WORKDIR /app

# Copy Go module files and download dependencies
# These files will be created in src/reverseproxy/ by 'go mod init'
COPY go.mod go.sum ./
RUN go mod download

# Copy all files from the src/reverseproxy directory into the container's /app directory
COPY . .

# Build the Go application from the current directory (src/reverseproxy/)
# Assumes main.go or other buildable Go source files are in this directory.
RUN go build -o reverseproxy_app .

# Expose the HTTP port your app listens on
EXPOSE 8080

# Run the compiled binary
CMD ["./reverseproxy_app"]

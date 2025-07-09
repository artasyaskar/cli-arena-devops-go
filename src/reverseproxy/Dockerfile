# Use official lightweight Go image
FROM golang:1.24-alpine

# Set working directory inside container
WORKDIR /app

# Copy Go module files and download dependencies
# These files are in src/reverseproxy/ relative to the build context (.)
COPY src/reverseproxy/go.mod src/reverseproxy/go.sum ./
RUN go mod download

# Copy all files from the src/reverseproxy directory (relative to build context) into the container's /app directory
COPY src/reverseproxy/ ./

# Build the Go application from the current directory (/app, which now contains the reverseproxy source)
# Assumes main.go or other buildable Go source files are in this directory.
RUN go build -o reverseproxy_app .

# Expose the HTTP port your app listens on
EXPOSE 8080

# Run the compiled binary
CMD ["./reverseproxy_app"]

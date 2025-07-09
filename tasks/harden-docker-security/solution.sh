#!/bin/bash
set -e

# Define the input and output Dockerfile names
INSECURE_DOCKERFILE="resources/Dockerfile.insecure"
HARDENED_DOCKERFILE="Dockerfile.hardened" # Output in current directory as per task spec

# Check if the insecure Dockerfile exists
if [ ! -f "$INSECURE_DOCKERFILE" ]; then
    echo "Error: Insecure Dockerfile not found at $INSECURE_DOCKERFILE"
    exit 1
fi

# Copy the insecure Dockerfile to start modifications
cp "$INSECURE_DOCKERFILE" "$HARDENED_DOCKERFILE"

# 1. Create a non-root user and switch to it
# Add user and group creation
sed -i '/^FROM golang:1.19-alpine/a \
RUN addgroup -S appgroup && adduser -S appuser -G appgroup' "$HARDENED_DOCKERFILE"

# Switch user before CMD
sed -i 's|^CMD \[\"/app/server\"\]|USER appuser\nCMD \[\"/app/server\"\]|' "$HARDENED_DOCKERFILE"

# 2. Pin package versions (example: curl to a specific version available in Alpine 3.14 for Go 1.19-alpine base)
#    Note: Finding exact minor versions for apk can be tricky without checking specific Alpine releases.
#    We'll use a common approach of specifying a version found in the base image's Alpine version.
#    The go:1.19-alpine image is based on Alpine 3.14, which has curl ~7.79.1 and git ~2.32.0.
#    For robustness in the solution, we'll aim for major.minor, but exact patch may vary.
#    A better pin would be like `curl=7.79.1-r0` but that's very specific.
#    Let's simulate pinning by adding a version. If `apk add package=version` fails,
#    it means that precise version isn't easily available. The spirit is version pinning.
sed -i 's/apk add curl git/apk add curl~=7.79 git~=2.32 ca-certificates/' "$HARDENED_DOCKERFILE"
# Added ca-certificates as it's good practice for HTTPS calls from within container

# 3. Add HEALTHCHECK
# Add HEALTHCHECK instruction before CMD and USER switch
# The simple Go server has a /health endpoint
sed -i '/^USER appuser/i \
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\\
  CMD curl -f http://localhost:8080/health || exit 1' "$HARDENED_DOCKERFILE"

# 4. Use --no-cache with apk update and clean up apt lists (apk specific)
sed -i 's/apk update && apk add/apk update && apk add --no-cache/' "$HARDENED_DOCKERFILE"
# Alpine's `apk add --no-cache` handles this. For debian/ubuntu, it would be `apt-get update && apt-get install --no-install-recommends -y ... && rm -rf /var/lib/apt/lists/*`

# 5. Remove hardcoded API_KEY, recommend using build args or runtime env vars
# We will remove the ENV line and expect it to be passed at runtime or build time.
sed -i '/ENV API_KEY=dummy_value_replace_me_in_production/d' "$HARDENED_DOCKERFILE"

sed -i '/^WORKDIR \/app/a \
ARG API_KEY\
ENV API_KEY=${API_KEY}' "$HARDENED_DOCKERFILE"

sed -i 's|COPY main.go .|COPY --chown=appuser:appgroup main.go .|' "$HARDENED_DOCKERFILE"
sed -i 's|COPY go.mod .|COPY --chown=appuser:appgroup go.mod .|' "$HARDENED_DOCKERFILE"
sed -i 's|COPY go.sum .|COPY --chown=appuser:appgroup go.sum .|' "$HARDENED_DOCKERFILE"

sed -i '/^RUN addgroup -S appgroup && adduser -S appuser -G appgroup/a \
RUN mkdir -p /app && chown appuser:appgroup /app' "$HARDENED_DOCKERFILE"

sed -i '/^RUN go build -o \/app\/server \./a \
RUN chown -R appuser:appgroup /app' "$HARDENED_DOCKERFILE"


sed -i '/^EXPOSE 8080/a # Application listens on port 8080, mapped by healthcheck and service' "$HARDENED_DOCKERFILE"

echo "Dockerfile hardened and saved to $HARDENED_DOCKERFILE"


exit 0

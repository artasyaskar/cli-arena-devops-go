.PHONY: setup build serve test lint clean

# Variables
DOCKER_COMPOSE = docker-compose
GO_FILES = $(shell find . -name '*.go' -not -path "./vendor/*")
TF_FILES = $(shell find . -name '*.tf')
APP_NAME = cli-arena-devops-go
GO_CMD = go
DOCKER_CMD = docker

# Default target
all: build

setup:
	@echo "Installing dependencies and bootstrapping..."
	# Install Go if not present (basic check)
	@command -v $(GO_CMD) >/dev/null 2>&1 || { echo >&2 "Go is not installed. Please install Go."; exit 1; }
	# Install Docker if not present (basic check)
	@command -v $(DOCKER_CMD) >/dev/null 2>&1 || { echo >&2 "Docker is not installed. Please install Docker."; exit 1; }
	# Install docker-compose if not present (basic check)
	@command -v $(DOCKER_COMPOSE) >/dev/null 2>&1 || { echo >&2 "Docker Compose is not installed. Please install Docker Compose."; exit 1; }
	# Install golangci-lint for Go linting
	@command -v golangci-lint >/dev/null 2>&1 || { echo "Installing golangci-lint..."; go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest; }
	# Install tflint for Terraform linting
	@command -v tflint >/dev/null 2>&1 || { echo "Installing tflint (checking common paths)..."; \
		if ! command -v tflint >/dev/null 2>&1; then \
			curl -s https://api.github.com/repos/terraform-linters/tflint/releases/latest | \
			grep "browser_download_url.*_linux_amd64.zip" | cut -d : -f 2,3 | tr -d \" | wget -qi - -O /tmp/tflint.zip && \
			sudo unzip /tmp/tflint.zip -d /usr/local/bin && rm /tmp/tflint.zip && tflint --init || \
			echo "Failed to install tflint. Please install it manually."; \
		fi; \
	}
	@echo "Setup complete."

build:
	@echo "Building Go application and Docker images..."
	# Example: Build a Go binary (adjust as needed)
	# $(GO_CMD) build -o bin/$(APP_NAME) ./src/...
	$(DOCKER_COMPOSE) build --no-cache
	@echo "Build complete."

serve: build
	@echo "Launching application using Docker..."
	$(DOCKER_COMPOSE) up -d
	@echo "Application is running. Access at http://localhost:8080 (if applicable)."

test:
	@echo "Running all tests..."
	# Run Go application tests
	@echo "Running Go application tests (if any)..."
	(cd src/reverseproxy && $(GO_CMD) test ./... -v)
	# Example: Run tests within a Docker container if needed
	# $(DOCKER_COMPOSE) exec -T app go test ./... -v
	@echo "Running task tests..."
	@if [ -d "tasks" ]; then \
		for task_dir in tasks/*/; do \
			if [ -f "$${task_dir}tests/run_tests.sh" ]; then \
				echo "Running tests in $${task_dir}"; \
				(cd "$${task_dir}" && bash tests/run_tests.sh); \
			elif [ -f "$${task_dir}tests/test_*.sh" ]; then \
				echo "Running sh tests in $${task_dir}tests/"; \
				for test_file in $${task_dir}tests/test_*.sh; do \
					echo "Executing $${test_file}"; \
					(bash "$${test_file}"); \
				done; \
			fi; \
		done; \
	fi
	@echo "All tests complete."

lint:
	@echo "Linting Go and Terraform files..."
	@echo "Linting Go files..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		(cd src/reverseproxy && golangci-lint run ./...); \
	else \
		echo "golangci-lint not found. Please run 'make setup'."; \
	fi
	@echo "Linting Terraform files..."
	@if command -v tflint >/dev/null 2>&1; then \
		if [ -n "$(TF_FILES)" ]; then \
			tflint --recursive; \
		else \
			echo "No Terraform files found to lint."; \
		fi; \
	else \
		echo "tflint not found. Please run 'make setup'."; \
	fi
	@echo "Linting complete."

clean:
	@echo "Cleaning up..."
	$(DOCKER_COMPOSE) down --volumes --remove-orphans
	# rm -rf bin/
	# $(GO_CMD) clean -cache -testcache -modcache
	@echo "Cleanup complete."

# Help target to display available commands
help:
	@echo "Available targets:"
	@echo "  setup          - Install dependencies and bootstrap configuration."
	@echo "  build          - Compile Go code and build Docker images."
	@echo "  serve          - Launch application using Docker."
	@echo "  test           - Run all tests."
	@echo "  lint           - Lint all Go/Terraform files."
	@echo "  clean          - Clean up generated files and Docker containers/volumes."
	@echo "  help           - Show this help message."

.DEFAULT_GOAL := help

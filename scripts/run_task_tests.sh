#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
  echo "Usage: ./scripts/run_task_tests.sh <task_id>"
  echo "Example: ./scripts/run_task_tests.sh harden-docker-security"
  exit 1
fi

TASK_ID=$1
TASK_DIR="tasks/$TASK_ID"

if [ ! -d "$TASK_DIR" ]; then
  echo "Error: Task directory '$TASK_DIR' not found."
  exit 1
fi

echo "INFO: Running tests for task '$TASK_ID' in directory '$TASK_DIR'..."

TEST_SCRIPT_PATH_GENERIC="$TASK_DIR/tests/run_tests.sh"
# Fallback to looking for specific test files if run_tests.sh is not present
# This logic is similar to the Makefile's test discovery.

if [ -f "$TEST_SCRIPT_PATH_GENERIC" ]; then
  echo "INFO: Found general test runner '$TEST_SCRIPT_PATH_GENERIC'."
  (cd "$TASK_DIR" && bash "$TEST_SCRIPT_PATH_GENERIC")
  echo "INFO: Tests for task '$TASK_ID' completed using '$TEST_SCRIPT_PATH_GENERIC'."
else
  echo "INFO: '$TEST_SCRIPT_PATH_GENERIC' not found. Looking for individual test_*.sh files in '$TASK_DIR/tests/'..."
  FOUND_SPECIFIC_TESTS=false
  for test_file in "$TASK_DIR"/tests/test_*.sh; do
    if [ -f "$test_file" ]; then
      FOUND_SPECIFIC_TESTS=true
      echo "INFO: Executing specific test file '$test_file'..."
      (bash "$test_file") # Run in a subshell to isolate environment
      echo "INFO: Specific test '$test_file' completed."
    fi
  done

  if [ "$FOUND_SPECIFIC_TESTS" = false ]; then
    echo "WARN: No 'run_tests.sh' or 'test_*.sh' files found in '$TASK_DIR/tests/' for task '$TASK_ID'."
    exit 1 # Considered a failure if no tests are found to run for the specified task.
  else
    echo "INFO: All found specific tests for task '$TASK_ID' completed."
  fi
fi

exit 0

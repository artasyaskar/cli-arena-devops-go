#!/usr/bin/env bash
set -e # Exit immediately if a command exits with a non-zero status.

TASK_ROOT_DIR=$(pwd)
RESOURCES_DIR="$TASK_ROOT_DIR/resources"
TERRAFORM_PROJECT_DIR="$RESOURCES_DIR/terraform_project"
SETUP_S3_BACKEND_SCRIPT="$RESOURCES_DIR/setup_initial_s3_backend.sh"
SOLUTION_SCRIPT="$TASK_ROOT_DIR/solution.sh"
VERIFY_SCRIPT="$TASK_ROOT_DIR/verify.sh"

# Original files to be potentially restored if test fails mid-way or for re-runs
BACKEND_TF_ORIGINAL_CONTENT=$(cat "$TERRAFORM_PROJECT_DIR/backend.tf")

cleanup_terraform_artifacts() {
    echo "INFO: Cleaning up Terraform artifacts in $TERRAFORM_PROJECT_DIR..."
    rm -f "$TERRAFORM_PROJECT_DIR/terraform.tfstate" # Local state if any
    rm -f "$TERRAFORM_PROJECT_DIR/terraform.tfstate.backup"
    rm -f "$TERRAFORM_PROJECT_DIR/.terraform.lock.hcl"
    rm -rf "$TERRAFORM_PROJECT_DIR/.terraform"
    rm -f "$TERRAFORM_PROJECT_DIR/s3_backend_details.txt"
    rm -f "$TERRAFORM_PROJECT_DIR/gcs_backend_details.txt"
    rm -f "$TERRAFORM_PROJECT_DIR/plan_after_migration.txt" # From solution
    rm -f "$TERRAFORM_PROJECT_DIR/verify_plan_no_changes.txt" # From verify
    # Restore original backend.tf
    echo "$BACKEND_TF_ORIGINAL_CONTENT" > "$TERRAFORM_PROJECT_DIR/backend.tf"
}

# AWS resource cleanup function (mocked unless real credentials are used)
# This function needs to read S3_BUCKET_NAME and DYNAMODB_TABLE_NAME from s3_backend_details.txt
cleanup_aws_resources() {
    echo "INFO: Cleaning up AWS resources (S3 bucket, DynamoDB table)..."
    if [ -f "$TERRAFORM_PROJECT_DIR/s3_backend_details.txt" ]; then
        source "$TERRAFORM_PROJECT_DIR/s3_backend_details.txt"
        if [ -n "$S3_BUCKET_NAME" ]; then
            echo "Attempting to delete objects from S3 bucket: $S3_BUCKET_NAME"
            aws s3 rm "s3://$S3_BUCKET_NAME" --recursive || echo "WARN: Failed to delete objects from $S3_BUCKET_NAME or bucket was empty."
            echo "Attempting to delete S3 bucket: $S3_BUCKET_NAME"
            aws s3rb "s3://$S3_BUCKET_NAME" --force || echo "WARN: Failed to delete S3 bucket $S3_BUCKET_NAME. It might have already been deleted or access issues."
        fi
        if [ -n "$DYNAMODB_TABLE_NAME" ]; then
            echo "Attempting to delete DynamoDB table: $DYNAMODB_TABLE_NAME"
            aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME" || echo "WARN: Failed to delete DynamoDB table $DYNAMODB_TABLE_NAME. It might have already been deleted or access issues."
        fi
    else
        echo "INFO: s3_backend_details.txt not found, skipping AWS resource cleanup."
    fi
}

# GCS resource cleanup function (mocked unless real credentials are used)
# This function needs to read GCS_BUCKET_NAME from gcs_backend_details.txt
cleanup_gcs_resources() {
    echo "INFO: Cleaning up GCS resources (GCS bucket)..."
     if [ -f "$TERRAFORM_PROJECT_DIR/gcs_backend_details.txt" ]; then
        source "$TERRAFORM_PROJECT_DIR/gcs_backend_details.txt"
        if [ -n "$GCS_BUCKET_NAME" ]; then
            echo "Attempting to delete objects from GCS bucket: $GCS_BUCKET_NAME (using gsutil rm -r -f)"
            # gsutil typically requires -f for non-empty buckets with -r, and might ask for confirmation if many objects.
            # For a test, this is a best effort. If gsutil is not configured, this will fail silently or error.
            (gsutil rm -r -f "gs://$GCS_BUCKET_NAME/*" && gsutil rb -f "gs://$GCS_BUCKET_NAME") || echo "WARN: Failed to delete GCS bucket $GCS_BUCKET_NAME or its contents. It might have already been deleted, not exist, or access issues."
        fi
    else
        echo "INFO: gcs_backend_details.txt not found, skipping GCS resource cleanup."
    fi
}


# Full cleanup routine
full_cleanup() {
    echo "INFO: === FULL CLEANUP ROUTINE STARTING ==="
    # In a real test environment with cloud access, these would be actual cloud resource deletions.
    # For a sandbox, these might be LocalStack or mock server calls.
    # Order: Terraform destroy (if state exists), then cloud resources, then local files.

    # Try to destroy any remaining Terraform-managed resources if state is accessible
    echo "INFO: Attempting 'terraform destroy' in $TERRAFORM_PROJECT_DIR (if initialized and state accessible)..."
    (cd "$TERRAFORM_PROJECT_DIR" && terraform init -input=false -no-color && terraform destroy -auto-approve -input=false -no-color -var="enable_gcs_test_pet_creation=true") || echo "WARN: Terraform destroy failed or not applicable."

    cleanup_aws_resources
    cleanup_gcs_resources # GCS cleanup should happen after TF destroy using GCS backend
    cleanup_terraform_artifacts
    echo "INFO: === FULL CLEANUP ROUTINE FINISHED ==="
}
trap full_cleanup EXIT # Ensure cleanup happens on script exit

echo "INFO: Starting test for 'migrate_terraform_backend_s3_to_gcs' task..."
echo "Current directory: $(pwd)"
if [ ! -f "./task.yaml" ]; then
    echo "ERROR: This test script must be run from the root of the 'migrate_terraform_backend_s3_to_gcs' task directory."
    exit 1
fi

# Make helper scripts executable
chmod +x "$SETUP_S3_BACKEND_SCRIPT"
chmod +x "$SOLUTION_SCRIPT"
chmod +x "$VERIFY_SCRIPT"


# Step 1: Setup initial S3 backend and state
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Setting up initial S3 backend and Terraform state..."
echo "---------------------------------------------------------------------"
# The setup script itself cds into resources/terraform_project, then comes back.
if ! "$SETUP_S3_BACKEND_SCRIPT"; then
    echo "❌ TEST FAIL: Initial S3 backend setup failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Initial S3 backend and state setup complete."


# Step 2: Run the solution script to migrate to GCS
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running solution script to migrate backend to GCS..."
echo "---------------------------------------------------------------------"
if ! "$SOLUTION_SCRIPT"; then
    echo "❌ TEST FAIL: Solution script for backend migration failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Solution script for backend migration executed successfully."


# Step 3: Run the verification script
echo "---------------------------------------------------------------------"
echo "INFO: STEP 3 - Running verification script..."
echo "---------------------------------------------------------------------"
# The verify script cds into terraform_project and performs checks.
if ! "$VERIFY_SCRIPT"; then
    echo "❌ TEST FAIL: Verification script failed."
    exit 1 # Trap will call full_cleanup
fi
echo "✅ Verification script executed successfully and confirmed backend migration."

# Note: The main cleanup is handled by the trap.
# Explicitly state test passed before trap runs for successful exit.
echo "---------------------------------------------------------------------"
echo "✅✅✅ TEST PASSED: 'migrate_terraform_backend_s3_to_gcs' task test completed successfully."
echo "---------------------------------------------------------------------"

# Disable trap for successful exit to avoid re-running cleanup if not needed, or let it run for full cleanup.
# For CI, letting trap run is usually fine.
exit 0

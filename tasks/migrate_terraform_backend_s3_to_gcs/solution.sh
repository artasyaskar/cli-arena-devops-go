#!/usr/bin/env bash
set -e

TERRAFORM_DIR="./resources/terraform_project"
BACKEND_TF_FILE="$TERRAFORM_DIR/backend.tf"
GCS_DETAILS_FILE="$TERRAFORM_DIR/gcs_backend_details.txt" # For documenting chosen GCS bucket/prefix

# Ensure script is run from the task's root directory
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "ERROR: Terraform project directory '$TERRAFORM_DIR' not found. Run this script from the task root."
    exit 1
fi

# Step 1: Define GCS bucket name and prefix
# For a real scenario, the user/agent would need to ensure this GCS bucket exists and they have permissions.
# For this task, we'll assume the bucket can be created or already exists and is accessible by gcloud CLI.
# The verify script might need to mock gsutil interactions if live GCS is not available.
RANDOM_GCS_SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
GCS_BUCKET_NAME="tf-gcs-backend-migrated-${RANDOM_GCS_SUFFIX}" # Needs to be globally unique
GCS_STATE_PREFIX="terraform/project_state" # Example prefix

# GCP Project ID - this should be configured in the environment or gcloud CLI.
# Attempt to get it from gcloud config, or use a placeholder.
GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "your-gcp-project-id-placeholder")
if [[ "$GCP_PROJECT_ID" == "your-gcp-project-id-placeholder" ]]; then
    echo "WARN: GCP Project ID not found via 'gcloud config get-value project'. Using placeholder."
    echo "WARN: Ensure your GCP project is correctly configured for Terraform GCS backend."
fi


echo "INFO: Starting Terraform backend migration from S3 to GCS."
echo "INFO: Target GCS Bucket: $GCS_BUCKET_NAME"
echo "INFO: Target GCS Prefix: $GCS_STATE_PREFIX"
echo "INFO: Using GCP Project: $GCP_PROJECT_ID"

# (Optional but good practice) Create the GCS bucket using gsutil if it doesn't exist.
# This step might be outside the direct Terraform flow but necessary in reality.
# For the task, we assume the agent can ensure the bucket exists.
# The verify script will mock gsutil if needed.
echo "INFO: Simulating GCS bucket creation for '$GCS_BUCKET_NAME' (if not exists)..."
# In a real environment:
# gsutil mb -p "$GCP_PROJECT_ID" "gs://$GCS_BUCKET_NAME" || echo "Bucket already exists or failed to create."
# gsutil versioning set on "gs://$GCS_BUCKET_NAME" || echo "Failed to enable versioning."
# For this script, we'll just proceed.

# Step 2: Update backend.tf with GCS configuration
echo "INFO: Updating $BACKEND_TF_FILE to use GCS backend..."
cat << EOF > "$BACKEND_TF_FILE"
terraform {
  backend "gcs" {
    bucket  = "$GCS_BUCKET_NAME"
    prefix  = "$GCS_STATE_PREFIX"
    project = "$GCP_PROJECT_ID" # Required for GCS backend
    # credentials = "/path/to/service-account.json" # Optional: if not using Application Default Credentials
  }
}
EOF
echo "$BACKEND_TF_FILE updated for GCS."

# Step 3: Perform state migration using `terraform init -migrate-state`
cd "$TERRAFORM_DIR"
echo "INFO: Running 'terraform init -migrate-state' in $(pwd) to migrate state to GCS..."
# Terraform will prompt "Do you want to copy existing state to the new backend?" Answer "yes".
# Terraform will also prompt "Do you want to delete the existing state from the S3 backend?" For safety, usually "no" initially.
# We can try to automate "yes" for copy. Deletion is riskier.
# For this automated solution, we assume `terraform init -migrate-state -input=false -force-copy` might work for non-interactive,
# or we provide "yes" via stdin. `-force-copy` is the key for non-interactive copy.
terraform init -migrate-state -force-copy -input=false -no-color
# The `-force-copy` flag tells Terraform to copy state without prompting.
# It does not automatically delete the source state.

echo "INFO: State migration process initiated."
# Note: `terraform init -migrate-state` copies the state. It does not delete the old S3 state by default.
# Deleting the old state from S3 would be a manual step afterwards if desired.

# Step 4: Verify no changes after migration
echo "INFO: Running 'terraform plan' to verify no changes to infrastructure..."
terraform plan -input=false -no-color -detailed-exitcode > plan_after_migration.txt || \
  ( [ $? -eq 0 ] || (echo "Plan shows changes or errored! Output in plan_after_migration.txt" && exit 1) )
# Exit code 0 means success (no changes). Exit code 2 means success (changes present). We want 0.
# The complex condition above means: if exit code is not 0 (no changes), then it's an error for this step.

if grep -q "No changes. Your infrastructure matches the configuration." plan_after_migration.txt; then
    echo "✅ SUCCESS: 'terraform plan' shows no changes. State migration appears successful."
else
    echo "❌ FAIL: 'terraform plan' indicates changes or did not confirm 'No changes'."
    cat plan_after_migration.txt
    cd ../.. # Back to task root
    exit 1
fi
rm plan_after_migration.txt


# Step 5: Document GCS details
echo "INFO: Documenting GCS backend details..."
cat << EOF_GCS_DETAILS > "$GCS_DETAILS_FILE"
GCS_BUCKET_NAME=$GCS_BUCKET_NAME
GCS_STATE_PREFIX=$GCS_STATE_PREFIX
GCP_PROJECT_ID=$GCP_PROJECT_ID
EOF_GCS_DETAILS
echo "GCS backend details saved to $GCS_DETAILS_FILE"

# Optional: Test applying a new resource using GCS backend (verify.sh will do this more robustly)
# echo "INFO: Testing GCS backend by planning a new resource..."
# terraform apply -auto-approve -input=false -no-color -var="enable_gcs_test_pet_creation=true"
# echo "INFO: Destroying the test resource..."
# terraform destroy -auto-approve -input=false -no-color -var="enable_gcs_test_pet_creation=true"

cd ../.. # Back to task root
echo "INFO: Terraform backend migration solution script completed."
exit 0

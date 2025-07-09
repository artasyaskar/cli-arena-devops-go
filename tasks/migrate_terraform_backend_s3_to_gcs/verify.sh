#!/usr/bin/env bash
set -e

TERRAFORM_DIR="./resources/terraform_project"
BACKEND_TF_FILE="$TERRAFORM_DIR/backend.tf"
GCS_DETAILS_FILE="$TERRAFORM_DIR/gcs_backend_details.txt"
S3_DETAILS_FILE="$TERRAFORM_DIR/s3_backend_details.txt" # Created by setup script

echo "INFO: Starting verification for Terraform backend migration (S3 to GCS)."

# Check 1: Ensure required files exist
if [ ! -f "$BACKEND_TF_FILE" ]; then
    echo "❌ FAIL: Terraform backend configuration file '$BACKEND_TF_FILE' not found."
    exit 1
fi
if [ ! -f "$GCS_DETAILS_FILE" ]; then
    echo "❌ FAIL: GCS backend details file '$GCS_DETAILS_FILE' not found. Solution might not have run or documented details."
    exit 1
fi
if [ ! -f "$S3_DETAILS_FILE" ]; then
    echo "❌ FAIL: S3 backend details file '$S3_DETAILS_FILE' not found. Setup script might not have run."
    exit 1
fi
echo "✅ PASS: Required files found."

# Load GCS and S3 details
source "$GCS_DETAILS_FILE" # Loads GCS_BUCKET_NAME, GCS_STATE_PREFIX
source "$S3_DETAILS_FILE"   # Loads S3_BUCKET_NAME, DYNAMODB_TABLE_NAME

if [ -z "$GCS_BUCKET_NAME" ] || [ -z "$GCS_STATE_PREFIX" ]; then
    echo "❌ FAIL: GCS_BUCKET_NAME or GCS_STATE_PREFIX not found in $GCS_DETAILS_FILE."
    exit 1
fi
if [ -z "$S3_BUCKET_NAME" ]; then # DYNAMODB_TABLE_NAME is less critical for post-migration verify
    echo "❌ FAIL: S3_BUCKET_NAME not found in $S3_DETAILS_FILE."
    exit 1
fi
echo "INFO: Loaded GCS bucket: $GCS_BUCKET_NAME, Prefix: $GCS_STATE_PREFIX"
echo "INFO: Original S3 bucket was: $S3_BUCKET_NAME"


# Check 2: Verify backend.tf is configured for GCS
echo "INFO: Verifying '$BACKEND_TF_FILE' for GCS configuration..."
if grep -q 'backend "gcs"' "$BACKEND_TF_FILE" && \
   grep -q "bucket *= *\"$GCS_BUCKET_NAME\"" "$BACKEND_TF_FILE" && \
   grep -q "prefix *= *\"$GCS_STATE_PREFIX\"" "$BACKEND_TF_FILE"; then
    echo "✅ PASS: '$BACKEND_TF_FILE' seems correctly configured for GCS backend."
else
    echo "❌ FAIL: '$BACKEND_TF_FILE' does not appear to be correctly configured for GCS backend."
    echo "Expected 'backend \"gcs\"', bucket '$GCS_BUCKET_NAME', and prefix '$GCS_STATE_PREFIX'."
    cat "$BACKEND_TF_FILE"
    exit 1
fi

# Navigate to Terraform directory for subsequent commands
cd "$TERRAFORM_DIR"

# Check 3: Terraform init with GCS backend (should not prompt for migration again)
echo "INFO: Running 'terraform init' to confirm GCS backend is recognized..."
# If migration was successful, subsequent init should just initialize the GCS backend.
# We expect it to not error out and not try to migrate again.
if terraform init -input=false -no-color; then
    echo "✅ PASS: 'terraform init' successful with GCS backend."
else
    echo "❌ FAIL: 'terraform init' failed after migration. GCS backend might not be configured correctly or state is problematic."
    cd ../..; exit 1 # Go back to task root before exiting
fi

# Check 4: `terraform plan` shows no changes for existing resources
echo "INFO: Verifying 'terraform plan' shows no changes for existing infrastructure..."
PLAN_OUTPUT_NO_CHANGES="verify_plan_no_changes.txt"
# Expect exit code 0 (no changes)
terraform plan -input=false -no-color -detailed-exitcode > "$PLAN_OUTPUT_NO_CHANGES" || \
    ([ $? -eq 0 ] || (echo "❌ FAIL: 'terraform plan' after migration indicates changes or errored." && cat "$PLAN_OUTPUT_NO_CHANGES" && cd ../.. && rm -f "$PLAN_OUTPUT_NO_CHANGES" && exit 1))

if grep -q "No changes. Your infrastructure matches the configuration." "$PLAN_OUTPUT_NO_CHANGES"; then
    echo "✅ PASS: 'terraform plan' confirms no changes to existing infrastructure after migration."
else
    echo "❌ FAIL: 'terraform plan' did not confirm 'No changes'. Output:"
    cat "$PLAN_OUTPUT_NO_CHANGES"
    rm -f "$PLAN_OUTPUT_NO_CHANGES"; cd ../..; exit 1
fi
rm -f "$PLAN_OUTPUT_NO_CHANGES"


# Check 5: Simulate GCS state file existence (gsutil ls gs://<bucket>/<prefix>/default.tfstate)
# This is a mock check. In a real environment with gcloud configured, this would be a live command.
# For the sandbox, we assume if `terraform init` and `plan` worked with GCS backend, state is there.
# A more robust mock would involve solution.sh creating a marker file.
# For now, we trust Terraform's successful plan post-migration.
echo "INFO: Simulating check for state file in GCS (gs://"$GCS_BUCKET_NAME"/"$GCS_STATE_PREFIX"/default.tfstate)..."
# If `terraform workspace show` returns "default", it implies state is being read.
CURRENT_WORKSPACE=$(terraform workspace show)
if [ "$CURRENT_WORKSPACE" == "default" ]; then
    echo "✅ PASS: Terraform workspace is 'default', implying state read from GCS is likely successful."
else
    echo "❌ WARN: Terraform workspace is '$CURRENT_WORKSPACE', not 'default'. This is unusual for a simple migration verification."
    # Not a hard fail, but a warning.
fi

# Check 6: Test applying and destroying a new dummy resource using GCS backend
echo "INFO: Testing GCS backend by applying and destroying a new dummy resource (random_pet)..."
# Enable the test pet resource
if terraform apply -auto-approve -input=false -no-color -var="enable_gcs_test_pet_creation=true"; then
    echo "✅ PASS: Successfully applied a new resource using GCS backend."
    # Verify it shows up in state list (another way to check state interaction)
    if terraform state list | grep -q "random_pet.gcs_test_pet"; then
        echo "✅ PASS: New resource 'random_pet.gcs_test_pet' found in Terraform state (GCS backend)."
    else
        echo "❌ FAIL: New resource 'random_pet.gcs_test_pet' NOT found in Terraform state list after apply."
        terraform state list
        cd ../..; exit 1
    fi

    # Now destroy it
    if terraform destroy -auto-approve -input=false -no-color -var="enable_gcs_test_pet_creation=true"; then
        echo "✅ PASS: Successfully destroyed the new resource using GCS backend."
    else
        echo "❌ FAIL: Failed to destroy the new resource using GCS backend."
        cd ../..; exit 1
    fi
else
    echo "❌ FAIL: Failed to apply a new resource using GCS backend."
    cd ../..; exit 1
fi


# Check 7: (Optional for verify, but good for task) Check if old S3 state still exists (it should, by default)
# This requires AWS CLI.
echo "INFO: Simulating check for old state file in S3 (s3://"$S3_BUCKET_NAME"/terraform.tfstate)..."
# In a real test with AWS CLI:
# if aws s3api head-object --bucket "$S3_BUCKET_NAME" --key "terraform.tfstate" >/dev/null 2>&1; then
#     echo "✅ INFO: Old state file still exists in S3 bucket '$S3_BUCKET_NAME' (as expected, migration only copies)."
# else
#     echo "WARN: Old state file does not exist in S3 bucket '$S3_BUCKET_NAME'. This is unexpected unless manually deleted."
# fi
# For this script, this is an informational check and not a pass/fail criteria for migration itself.

echo "------------------------------------------"
echo "✅✅✅ All Terraform backend migration verification tests passed."
# Navigate back to task root
cd ../..
echo "Current directory: $(pwd)"
exit 0

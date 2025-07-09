#!/bin/bash
set -e

INFRA_DIR="./resources/infra"
MAIN_TF_FILE_TO_CHECK="$INFRA_DIR/main.tf" # The file user modifies

echo "INFO: Starting verification for Terraform dependency debugging task."

# Check if main.tf exists (user should have modified it)
if [ ! -f "$MAIN_TF_FILE_TO_CHECK" ]; then
    echo "❌ FAIL: Terraform configuration file '$MAIN_TF_FILE_TO_CHECK' not found."
    exit 1
fi
echo "✅ PASS: Found Terraform file '$MAIN_TF_FILE_TO_CHECK'."

# Navigate to the Terraform configuration directory
cd "$INFRA_DIR"
echo "INFO: Current directory: $(pwd)"

# Cleanup function for Terraform state and lock files
cleanup_tf_files() {
  echo "INFO: Cleaning up local Terraform state and .terraform directory..."
  rm -f .terraform.lock.hcl
  rm -f debug_dependencies.tfstate* # remove state and backups
  rm -rf .terraform/
}
# Ensure local TF files are cleaned before starting and after finishing, especially on error
cleanup_tf_files
# Trap for final cleanup on exit
trap cleanup_tf_files EXIT


# Step 1: Terraform Init
echo "---------------------------------------------------------------------"
echo "INFO: STEP 1 - Running 'terraform init'..."
echo "---------------------------------------------------------------------"
if ! terraform init -input=false -no-color; then
    echo "❌ FAIL: 'terraform init' failed."
    exit 1
fi
echo "✅ PASS: 'terraform init' successful."

# Step 2: Terraform Validate
echo "---------------------------------------------------------------------"
echo "INFO: STEP 2 - Running 'terraform validate'..."
echo "---------------------------------------------------------------------"
if ! terraform validate -no-color; then
    echo "❌ FAIL: 'terraform validate' failed. Configuration is invalid."
    exit 1
fi
echo "✅ PASS: 'terraform validate' successful. Configuration is valid."

# Step 3: Terraform Apply
echo "---------------------------------------------------------------------"
echo "INFO: STEP 3 - Running 'terraform apply' (expecting successful creation)..."
echo "---------------------------------------------------------------------"
APPLY_LOG="terraform_apply.log"
if ! terraform apply -auto-approve -input=false -no-color > "$APPLY_LOG" 2>&1; then
    echo "❌ FAIL: 'terraform apply' failed. Resources may not have been created correctly or in order."
    cat "$APPLY_LOG"
    # Attempt to destroy any partially created resources
    echo "INFO: Attempting to destroy any partially created resources..."
    terraform destroy -auto-approve -input=false -no-color || echo "WARN: Destroy failed during error cleanup."
    rm -f "$APPLY_LOG"
    exit 1
fi
echo "✅ PASS: 'terraform apply' successful. All resources created."
# Verify that outputs were generated (implies resources were created)
if ! grep -q "vpc_id" "$APPLY_LOG" || \
   ! grep -q "public_subnet_id" "$APPLY_LOG" || \
   ! grep -q "igw_id" "$APPLY_LOG" || \
   ! grep -q "route_table_id" "$APPLY_LOG" || \
   ! grep -q "security_group_id" "$APPLY_LOG"; then
    echo "❌ WARN: Not all expected outputs found in apply log. This might indicate some resources were not created as expected."
    cat "$APPLY_LOG"
    # Not a hard fail if apply itself succeeded, but a strong warning.
else
    echo "✅ PASS: Expected outputs found in apply log."
fi
rm -f "$APPLY_LOG"

# Step 4: Check state list (optional, but good verification)
echo "---------------------------------------------------------------------"
echo "INFO: STEP 4 - Checking 'terraform state list' for expected resources..."
echo "---------------------------------------------------------------------"
STATE_LIST_LOG="terraform_state_list.log"
terraform state list > "$STATE_LIST_LOG"
EXPECTED_RESOURCES=(
    "aws_vpc.main_vpc"
    "aws_internet_gateway.gw"
    "aws_internet_gateway_attachment.gw_attachment"
    "aws_subnet.public_subnet"
    "aws_route_table.public_route_table"
    "aws_route.public_route_to_igw"
    "aws_route_table_association.public_subnet_assoc"
    "aws_security_group.allow_http_ssh"
)
ALL_RESOURCES_FOUND=true
for resource in "${EXPECTED_RESOURCES[@]}"; do
    if ! grep -q "$resource" "$STATE_LIST_LOG"; then
        echo "❌ FAIL: Expected resource '$resource' not found in terraform state list."
        ALL_RESOURCES_FOUND=false
    fi
done
rm -f "$STATE_LIST_LOG"

if [ "$ALL_RESOURCES_FOUND" = true ]; then
    echo "✅ PASS: All expected resources found in terraform state list."
else
    echo "INFO: Full state list:"
    terraform state list # Print full list on failure
    # This is a hard failure because if apply succeeded, state should reflect it.
    exit 1
fi


# Step 5: Terraform Destroy
echo "---------------------------------------------------------------------"
echo "INFO: STEP 5 - Running 'terraform destroy'..."
echo "---------------------------------------------------------------------"
DESTROY_LOG="terraform_destroy.log"
if ! terraform destroy -auto-approve -input=false -no-color > "$DESTROY_LOG" 2>&1; then
    echo "❌ FAIL: 'terraform destroy' failed. Resources may not have been cleaned up properly."
    cat "$DESTROY_LOG"
    rm -f "$DESTROY_LOG"
    exit 1
fi
echo "✅ PASS: 'terraform destroy' successful. All resources removed."
rm -f "$DESTROY_LOG"

# Navigate back to task root before final exit (trap will also run in current dir)
cd ../..
echo "INFO: Current directory: $(pwd)"

echo "---------------------------------------------------------------------"
echo "✅✅✅ All Terraform dependency debugging verification steps passed."
echo "---------------------------------------------------------------------"
# Trap will handle final local file cleanup.
exit 0

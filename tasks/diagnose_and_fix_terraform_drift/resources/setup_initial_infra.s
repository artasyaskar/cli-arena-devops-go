#!/bin/bash
set -e
echo "INFO: Navigating to Terraform configuration directory: $(pwd)/resources"
# Ensure script is run from task's root directory or resources directory itself
if [ -d "./resources" ]; then
  cd ./resources
elif [ ! -f "./main.tf" ]; then
  echo "ERROR: This script must be run from the root of the 'diagnose_and_fix_terraform_drift' task directory or its 'resources' subdirectory."
  exit 1
fi

echo "INFO: Initializing Terraform..."
terraform init -input=false

echo "INFO: Applying initial Terraform configuration to create baseline resources..."
terraform apply -auto-approve -input=false

# Save outputs to a file for other scripts to use
terraform output -json > terraform_outputs.json

# Extract specific values for easier scripting later, if needed
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
ROLE_NAME=$(terraform output -raw iam_role_name)
INSTANCE_PROFILE_NAME=$(terraform output -raw iam_instance_profile_name)

echo "INFO: Baseline infrastructure created successfully."
echo "S3 Bucket Name: $BUCKET_NAME"
echo "IAM Role Name: $ROLE_NAME"
echo "IAM Instance Profile Name: $INSTANCE_PROFILE_NAME"
echo "Full outputs saved to terraform_outputs.json"

# Return to task root if we changed directory
if [ -d "../resources" ]; then # i.e. if we were in task root and cd'd into resources
    cd ..
fi

exit 0

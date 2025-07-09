#!/usr/bin/env bash
set -e

TERRAFORM_DIR="./resources/terraform_project"
BACKEND_TF_FILE="$TERRAFORM_DIR/backend.tf"
AWS_REGION_VAR=$(grep 'default     = "us-east-1"' "$TERRAFORM_DIR/variables.tf" | sed -n 's/.*default     = "\(.*\)".*/\1/p')
AWS_REGION=${AWS_REGION_VAR:-"us-east-1"} # Fallback if grep fails

# Generate unique names for S3 bucket and DynamoDB table
RANDOM_SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
S3_BUCKET_NAME="tf-s3-backend-test-${RANDOM_SUFFIX}"
DYNAMODB_TABLE_NAME="tf-locks-${RANDOM_SUFFIX}"

echo "INFO: Setting up initial S3 backend..."
echo "INFO: Using AWS Region: $AWS_REGION"
echo "INFO: Generated S3 Bucket Name: $S3_BUCKET_NAME"
echo "INFO: Generated DynamoDB Table Name: $DYNAMODB_TABLE_NAME"

# Create S3 bucket (ensure it's globally unique)
echo "INFO: Creating S3 bucket '$S3_BUCKET_NAME' in region '$AWS_REGION'..."
if aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null 2>&1; then
    echo "S3 bucket '$S3_BUCKET_NAME' created successfully."
else
    echo "WARN: Failed to create S3 bucket '$S3_BUCKET_NAME'. It might already exist if you have run this before with the same suffix, or there could be a permissions issue."
    echo "Attempting to proceed, assuming bucket exists and is accessible."
fi
# Enable versioning on the S3 bucket (good practice for tfstate)
aws s3api put-bucket-versioning --bucket "$S3_BUCKET_NAME" --versioning-configuration Status=Enabled


# Create DynamoDB table for state locking
echo "INFO: Creating DynamoDB table '$DYNAMODB_TABLE_NAME' for state locking..."
if aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --region "$AWS_REGION" > /dev/null 2>&1; then
    echo "DynamoDB table '$DYNAMODB_TABLE_NAME' creation initiated. Waiting for it to become active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME" --region "$AWS_REGION"
    echo "DynamoDB table '$DYNAMODB_TABLE_NAME' is active."
else
    echo "WARN: Failed to create DynamoDB table '$DYNAMODB_TABLE_NAME'. It might already exist or permissions issue."
    echo "Attempting to proceed, assuming table exists and is accessible."
fi


# Update backend.tf with the generated names
echo "INFO: Updating $BACKEND_TF_FILE with generated S3 backend configuration..."
cat << EOF > "$BACKEND_TF_FILE"
terraform {
  backend "s3" {
    bucket         = "$S3_BUCKET_NAME"
    key            = "terraform.tfstate" # Default key from variables.tf
    region         = "$AWS_REGION"
    dynamodb_table = "$DYNAMODB_TABLE_NAME"
    encrypt        = true # Good practice
  }
}
EOF
echo "$BACKEND_TF_FILE updated."

# Store the generated names for cleanup and for the solution script to know what to migrate from
cat << EOF > "$TERRAFORM_DIR/s3_backend_details.txt"
S3_BUCKET_NAME=$S3_BUCKET_NAME
DYNAMODB_TABLE_NAME=$DYNAMODB_TABLE_NAME
AWS_REGION=$AWS_REGION
EOF
echo "INFO: S3 backend details saved to $TERRAFORM_DIR/s3_backend_details.txt"


# Initialize Terraform in the project directory
cd "$TERRAFORM_DIR"
echo "INFO: Running 'terraform init' in $(pwd)..."
terraform init -input=false -no-color

# Apply initial configuration to create a state file in S3
echo "INFO: Running 'terraform apply' to create initial state in S3 backend..."
terraform apply -auto-approve -input=false -no-color

echo "INFO: Initial S3 backend setup and state creation complete."
echo "INFO: Terraform project in '$TERRAFORM_DIR' is now configured to use S3 backend:"
echo "  Bucket: $S3_BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE_NAME"

# Navigate back to task root if called from there
if [[ "$(basename $(pwd))" == "terraform_project" ]]; then
  cd ../.. # from resources/terraform_project to task root
fi

exit 0

#!/usr/bin/env bash
set -e

echo "INFO: Simulating drift on AWS resources..."

# Ensure script is run from task's root directory or resources directory itself
if [ -d "./resources" ]; then
  CD_TO_RESOURCES=true
  cd ./resources
elif [ ! -f "./main.tf" ]; then
  echo "ERROR: This script must be run from the root of the 'diagnose_and_fix_terraform_drift' task directory or its 'resources' subdirectory."
  exit 1
fi

# Check if terraform_outputs.json exists
if [ ! -f "terraform_outputs.json" ]; then
    echo "ERROR: terraform_outputs.json not found. Please run setup_initial_infra.sh first."
    if [ "$CD_TO_RESOURCES" = true ]; then cd ..; fi
    exit 1
fi

# Load outputs
BUCKET_NAME=$(jq -r '.s3_bucket_name.value' terraform_outputs.json)
ROLE_NAME=$(jq -r '.iam_role_name.value' terraform_outputs.json)
INSTANCE_PROFILE_NAME=$(jq -r '.iam_instance_profile_name.value' terraform_outputs.json)
AWS_REGION=$(jq -r '.aws_region.value // "us-east-1"' terraform_outputs.json) # Read region or default

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "null" ]; then
    echo "ERROR: Could not read S3 bucket name from terraform_outputs.json."
    if [ "$CD_TO_RESOURCES" = true ]; then cd ..; fi
    exit 1
fi
if [ -z "$ROLE_NAME" ] || [ "$ROLE_NAME" == "null" ]; then
    echo "ERROR: Could not read IAM role name from terraform_outputs.json."
    if [ "$CD_TO_RESOURCES" = true ]; then cd ..; fi
    exit 1
fi
if [ -z "$INSTANCE_PROFILE_NAME" ] || [ "$INSTANCE_PROFILE_NAME" == "null" ]; then
    echo "ERROR: Could not read IAM instance profile name from terraform_outputs.json."
    if [ "$CD_TO_RESOURCES" = true ]; then cd ..; fi
    exit 1
fi

echo "Target AWS Region: $AWS_REGION"
echo "Target S3 Bucket: $BUCKET_NAME"
echo "Target IAM Role: $ROLE_NAME"
echo "Target Instance Profile: $INSTANCE_PROFILE_NAME"

# Drift 1: Modify S3 bucket tags (add a new tag, modify an existing one)
echo "INFO: Modifying tags for S3 bucket $BUCKET_NAME..."
aws s3api put-bucket-tagging --region $AWS_REGION --bucket $BUCKET_NAME --tagging '{
    "TagSet": [
        {"Key": "Environment", "Value": "ProductionDrift"},
        {"Key": "Project", "Value": "TerraformDrift"},
        {"Key": "ManagedBy", "Value": "Terraform"},
        {"Key": "DriftTag", "Value": "AppliedManually"}
    ]
}'
echo "S3 bucket tags modified."

# Drift 2: Alter IAM role policy (e.g., add an Deny statement or remove a permission)
# For simplicity, let's add a new inline policy to the role that wasn't defined in TF
# This is easier to demonstrate drift than modifying the existing complex JSON policy.
NEW_POLICY_NAME="DriftDemoPolicy"
echo "INFO: Adding a new inline policy '$NEW_POLICY_NAME' to IAM role $ROLE_NAME..."
aws iam put-role-policy --region $AWS_REGION --role-name $ROLE_NAME --policy-name $NEW_POLICY_NAME --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Deny",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::'$BUCKET_NAME'/*"
        }
    ]
}'
echo "New inline policy '$NEW_POLICY_NAME' added to IAM role $ROLE_NAME."

# Drift 3: IAM Instance Profile - Detach the role from the instance profile
# (Instance profiles can only have one role. We can't "change" the role without first removing the existing one)
# This is a common drift scenario if someone manually changes EC2 instance associations.
# First, confirm the role is attached.
CURRENT_ROLES_ON_PROFILE=$(aws iam get-instance-profile --region $AWS_REGION --instance-profile-name $INSTANCE_PROFILE_NAME --query 'InstanceProfile.Roles[].RoleName' --output text)
if [[ "$CURRENT_ROLES_ON_PROFILE" == *"$ROLE_NAME"* ]]; then
    echo "INFO: Detaching role $ROLE_NAME from instance profile $INSTANCE_PROFILE_NAME..."
    aws iam remove-role-from-instance-profile --region $AWS_REGION --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $ROLE_NAME
    echo "Role $ROLE_NAME detached from instance profile $INSTANCE_PROFILE_NAME."
else
    echo "WARN: Role $ROLE_NAME was not found on instance profile $INSTANCE_PROFILE_NAME. Skipping detachment drift."
fi

# Drift 4: (Optional) Delete a tag from the IAM Role
echo "INFO: Deleting 'Project' tag from IAM role $ROLE_NAME..."
aws iam untag-role --region $AWS_REGION --role-name $ROLE_NAME --tag-keys "Project"
echo "'Project' tag deleted from IAM role $ROLE_NAME."


echo "INFO: Drift simulation complete."
echo "Summary of simulated drift:"
echo "  - S3 Bucket '$BUCKET_NAME': Tags modified (Environment changed, DriftTag added)."
echo "  - IAM Role '$ROLE_NAME': New inline policy '$NEW_POLICY_NAME' added. 'Project' tag removed."
echo "  - IAM Instance Profile '$INSTANCE_PROFILE_NAME': Role '$ROLE_NAME' detached."

# Return to task root if we changed directory
if [ "$CD_TO_RESOURCES" = true ]; then
    cd ..
fi

exit 0

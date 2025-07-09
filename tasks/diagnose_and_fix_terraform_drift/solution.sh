#!/bin/bash
set -e

echo "INFO: Starting Terraform drift remediation process."

# Navigate to the Terraform configuration directory if not already there.
# This script assumes it's run from the task's root directory.
if [ -d "./resources" ]; then
  cd ./resources
else
  echo "ERROR: Could not find ./resources directory. This script should be run from the root of the 'diagnose_and_fix_terraform_drift' task directory."
  exit 1
fi

echo "Current working directory: $(pwd)"

# Ensure Terraform is initialized (it should be if setup_initial_infra.sh was run)
echo "INFO: Ensuring Terraform is initialized..."
terraform init -input=false

# Step 1: Identify Drift
echo "INFO: Running 'terraform plan' to identify drift..."
terraform plan -input=false -detailed-exitcode > plan_output.txt || true
# The || true is because plan will exit with 2 if there's drift, which is expected.
# We capture the output for analysis.

echo "---------------------------------------------------------------------"
echo "INFO: Terraform Plan Output (saved to plan_output.txt):"
cat plan_output.txt
echo "---------------------------------------------------------------------"

# Step 2: Remediation Plan (documented as comments)
#
# **Remediation Plan for Terraform Drift**
#
# After reviewing the `terraform plan` output, the following drift has been identified:
#
# 1.  **S3 Bucket Tags (`aws_s3_bucket.data_bucket`):**
#     *   The `Environment` tag has changed from "Test" to "ProductionDrift".
#     *   A new tag `DriftTag` with value "AppliedManually" has been added.
#     *   *Remediation:* `terraform apply` will revert `Environment` to "Test" and remove `DriftTag`. This is desired.
#
# 2.  **IAM Role (`aws_iam_role.app_role`):**
#     *   A new inline policy named `DriftDemoPolicy` was manually added to the role.
#     *   *Remediation:* `terraform apply` will remove this inline policy as it's not defined in the Terraform configuration. This is desired.
#     *   The `Project` tag was removed from the role.
#     *   *Remediation:* `terraform apply` will re-add the `Project` tag with value "TerraformDrift". This is desired.
#
# 3.  **IAM Instance Profile (`aws_iam_instance_profile.app_instance_profile`):**
#     *   The role `TerraformDriftTestRole` (defined by `aws_iam_role.app_role.name`) was detached from the instance profile `TerraformDriftTestInstanceProfile`.
#     *   *Remediation:* `terraform apply` will re-associate the role `TerraformDriftTestRole` with the instance profile. This is desired.
#
# **Overall Strategy:**
# The `terraform apply` command should correct all identified drift by aligning the AWS resources
# with the configuration defined in `main.tf`. No resources are planned for destruction that shouldn't be.
# The changes are primarily additive (re-adding tags, re-associating roles) or corrective (removing untracked policies, correcting tag values).
#
# **Pre-Apply Checks:**
# -   Confirm that the AWS credentials and region are correctly configured for Terraform.
# -   Ensure no other manual changes are being made to these resources during the remediation.
#
# **Post-Apply Verification:**
# -   Run `terraform plan` again to ensure no further drift is detected.
# -   Manually inspect the resources in the AWS console (or via AWS CLI) to confirm they match `main.tf`.
#

echo "INFO: Remediation plan documented in solution.sh comments."
# Optionally, create a remediation_plan.txt
cat << EOF > remediation_plan.txt
**Remediation Plan for Terraform Drift**

After reviewing the \`terraform plan\` output, the following drift has been identified:

1.  **S3 Bucket Tags (\`aws_s3_bucket.data_bucket\`):**
    *   The \`Environment\` tag has changed from "Test" to "ProductionDrift".
    *   A new tag \`DriftTag\` with value "AppliedManually" has been added.
    *   *Remediation:* \`terraform apply\` will revert \`Environment\` to "Test" and remove \`DriftTag\`. This is desired.

2.  **IAM Role (\`aws_iam_role.app_role\`):**
    *   A new inline policy named \`DriftDemoPolicy\` was manually added to the role.
    *   *Remediation:* \`terraform apply\` will remove this inline policy as it's not defined in the Terraform configuration. This is desired.
    *   The \`Project\` tag was removed from the role.
    *   *Remediation:* \`terraform apply\` will re-add the \`Project\` tag with value "TerraformDrift". This is desired.

3.  **IAM Instance Profile (\`aws_iam_instance_profile.app_instance_profile\`):**
    *   The role \`TerraformDriftTestRole\` (defined by \`aws_iam_role.app_role.name\`) was detached from the instance profile \`TerraformDriftTestInstanceProfile\`.
    *   *Remediation:* \`terraform apply\` will re-associate the role \`TerraformDriftTestRole\` with the instance profile. This is desired.

**Overall Strategy:**
The \`terraform apply\` command should correct all identified drift by aligning the AWS resources
with the configuration defined in \`main.tf\`. No resources are planned for destruction that shouldn't be.
The changes are primarily additive (re-adding tags, re-associating roles) or corrective (removing untracked policies, correcting tag values).
EOF
echo "INFO: Remediation plan also saved to remediation_plan.txt."


# Step 3: Apply Changes to Remediate Drift
echo "INFO: Running 'terraform apply' to remediate the drift..."
terraform apply -auto-approve -input=false

echo "INFO: Drift remediation apply complete."

# Step 4: Verify No Further Drift
echo "INFO: Running 'terraform plan' again to verify no further drift..."
# Using -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes detected
if terraform plan -input=false -detailed-exitcode; then
    echo "SUCCESS: 'terraform plan' shows no further changes. Drift remediated successfully."
else
    PLAN_EXIT_CODE=$?
    if [ $PLAN_EXIT_CODE -eq 2 ]; then
        echo "ERROR: 'terraform plan' still shows changes. Drift not fully remediated."
        terraform plan -input=false # Show the plan
        # Go back to task root before exiting
        cd ..
        exit 1
    else
        echo "ERROR: 'terraform plan' failed with exit code $PLAN_EXIT_CODE."
        # Go back to task root before exiting
        cd ..
        exit 1
    fi
fi

# Go back to task root
cd ..
echo "Current working directory: $(pwd)"
echo "INFO: Terraform drift remediation process completed successfully."
exit 0

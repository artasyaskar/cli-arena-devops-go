#!/usr/bin/env bash
set -e # Exit on one error, but we want to report all failures. So, use a flag.

ENHANCED_WORKFLOW_FILE=".github/workflows/ci.enhanced.yml" # Expected output from solution
GO_APP_DIR="./resources/go_app"
TERRAFORM_INFRA_DIR="./resources/terraform_infra"

PASS_COUNT=0
FAIL_COUNT=0

# Helper function to print pass/fail and increment counts
check() {
    local description="$1"
    local condition_met=$2 # 0 for true (success), 1 for false (failure)

    if [ "$condition_met" -eq 0 ]; then
        echo "✅ PASS: $description"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ FAIL: $description"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "INFO: Starting verification for CI/CD Pipeline Optimization and Security task."
echo "INFO: Analyzing workflow file: $ENHANCED_WORKFLOW_FILE"

if [ ! -f "$ENHANCED_WORKFLOW_FILE" ]; then
  echo "❌ FAIL: Enhanced workflow file '$ENHANCED_WORKFLOW_FILE' not found. Run solution first."
  exit 1
fi

# Check 1: Caching
# Go module caching
grep -q "actions/cache@v" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "path: |" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "~/go/pkg/mod" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "key: \${{ runner.os }}-go-\${{ hashFiles('**/go.sum') }}" "$ENHANCED_WORKFLOW_FILE"
check "Go module caching is implemented." $?

# Terraform provider caching
grep -q "actions/cache@v" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "path: ~/.terraform.d/plugin-cache" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "key: \${{ runner.os }}-terraform-\${{ hashFiles('**/.terraform.lock.hcl') }}" "$ENHANCED_WORKFLOW_FILE"
check "Terraform provider caching is implemented." $?


# Check 2: Security Scans
# Gosec scan
grep -q "gosec" "$ENHANCED_WORKFLOW_FILE" && \
(grep -q "gosec -fmt=json" "$ENHANCED_WORKFLOW_FILE" || grep -q "gosec ./..." "$ENHANCED_WORKFLOW_FILE") && \
(grep -q "exit 1" "$ENHANCED_WORKFLOW_FILE" && grep -q "Gosec found HIGH severity issues" "$ENHANCED_WORKFLOW_FILE") # Check for fail condition
check "Gosec scan is integrated and configured to fail on HIGH severity." $?

# tfsec/checkov scan (assuming tfsec for this check)
grep -q "tfsec" "$ENHANCED_WORKFLOW_FILE" && \
(grep -q "tfsec --format json" "$ENHANCED_WORKFLOW_FILE" || grep -q "tfsec ." "$ENHANCED_WORKFLOW_FILE") && \
(grep -q "exit 1" "$ENHANCED_WORKFLOW_FILE" && grep -q "tfsec found HIGH or CRITICAL severity issues" "$ENHANCED_WORKFLOW_FILE") # Check for fail condition
check "tfsec scan is integrated and configured to fail on HIGH/CRITICAL severity." $?


# Check 3: Secrets usage
grep -q "\${{ secrets.AWS_ACCESS_KEY_ID_MOCK" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "\${{ secrets.AWS_SECRET_ACCESS_KEY_MOCK" "$ENHANCED_WORKFLOW_FILE"
check "Workflow demonstrates usage of GitHub secrets for AWS credentials." $?


# Check 4: Workflow Logic
# Terraform plan on PRs to main
WORKFLOW_YAML_CONTENT=$(cat "$ENHANCED_WORKFLOW_FILE") # Read once for multiple checks
# This check is a bit simplistic, relies on job name and if condition.
# A proper YAML parser would be better.
if echo "$WORKFLOW_YAML_CONTENT" | grep -A 5 "name: Terraform Plan and Scan" | grep -q "if: github.event_name == 'pull_request' && github.base_ref == 'main'"; then
    tf_plan_condition_met=0
else
    tf_plan_condition_met=1
fi
check "Terraform plan job is configured to run on PRs to main branch." "$tf_plan_condition_met"

# Terraform apply manually triggered (workflow_dispatch)
if echo "$WORKFLOW_YAML_CONTENT" | grep -A 5 "name: Terraform Apply" | grep -q "if: github.event_name == 'workflow_dispatch'"; then
    tf_apply_manual_trigger_met=0
else
    # Also check if workflow_dispatch is defined at the top level 'on:'
    if grep -A 3 "^on:" "$ENHANCED_WORKFLOW_FILE" | grep -q "workflow_dispatch:"; then
         if echo "$WORKFLOW_YAML_CONTENT" | grep -A 5 "name: Terraform Apply" | grep -q "if: github.event_name == 'workflow_dispatch'"; then
            tf_apply_manual_trigger_met=0
         else
            tf_apply_manual_trigger_met=1
         fi
    else
        tf_apply_manual_trigger_met=1
    fi
fi
check "Terraform apply job is manually triggerable via workflow_dispatch." "$tf_apply_manual_trigger_met"


# Terraform plan artifact upload and download
grep -A 3 "name: Upload Terraform Plan Artifact" "$ENHANCED_WORKFLOW_FILE" | grep -q "path: ./resources/terraform_infra/plan.tfplan" && \
grep -A 3 "name: Download Terraform Plan Artifact" "$ENHANCED_WORKFLOW_FILE" | grep -q "name: terraform-plan"
check "Terraform plan artifact (plan.tfplan) is uploaded and downloaded." $?

# (Harder) PR Commenting - Check for conceptual presence
grep -q "Post Terraform Plan to PR" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "actions/github-script@v" "$ENHANCED_WORKFLOW_FILE" && \
grep -q "github.rest.issues.createComment" "$ENHANCED_WORKFLOW_FILE"
check "(Harder) Step for posting Terraform plan to PR comment is present." $?


# Check 5: Go Testing enhancements
# Go test with -race flag
grep -A 2 "name: Test Go App with Race Detector and Coverage" "$ENHANCED_WORKFLOW_FILE" | grep -q "go test -race"
check "Go tests are run with the -race flag." $?

# Go test coverage report upload
grep -A 3 "name: Upload Go Test Coverage Report" "$ENHANCED_WORKFLOW_FILE" | grep -q "path: ./resources/go_app/coverage.out"
check "Go test coverage report (coverage.out) is uploaded as an artifact." $?

# Check 6: (Optional local execution) Run gosec and tfsec locally if available
# This confirms the tools *would* find issues in the provided code.
GOLANG_INSTALLED=$(go version > /dev/null 2>&1; echo $?)
TFSEC_INSTALLED=$(tfsec --version > /dev/null 2>&1; echo $?)
GOSEC_INSTALLED=$(gosec --version > /dev/null 2>&1; echo $?)


if [ "$GOLANG_INSTALLED" -eq 0 ] && [ "$GOSEC_INSTALLED" -eq 0 ]; then
    echo "INFO: Attempting to run gosec locally on $GO_APP_DIR..."
    # Run gosec, expect it to find issues (exit code 1 for findings by default)
    # We use -no-fail and check output, similar to workflow.
    (cd "$GO_APP_DIR" && gosec -no-fail -fmt=json -out=verify-gosec.json ./... || true)
    if jq -e '.Issues[] | select(.severity == "HIGH")' "$GO_APP_DIR/verify-gosec.json"; then
        check "Local gosec run found expected HIGH severity issues in sample Go code." 0
    else
        check "Local gosec run did NOT find expected HIGH severity issues in sample Go code." 1
        echo "Gosec output:"
        jq . "$GO_APP_DIR/verify-gosec.json"
    fi
    rm -f "$GO_APP_DIR/verify-gosec.json"
else
    echo "INFO: Go or Gosec not found locally, skipping local gosec execution check."
fi

if [ "$TFSEC_INSTALLED" -eq 0 ]; then
    echo "INFO: Attempting to run tfsec locally on $TERRAFORM_INFRA_DIR..."
    # Run tfsec, expect it to find issues
    (cd "$TERRAFORM_INFRA_DIR" && tfsec --no-fail --format json --out verify-tfsec.json . || true)
    if jq -e '.results[] | select(.severity == "CRITICAL" or .severity == "HIGH")' "$TERRAFORM_INFRA_DIR/verify-tfsec.json"; then
        check "Local tfsec run found expected HIGH/CRITICAL issues in sample Terraform code." 0
    else
        check "Local tfsec run did NOT find expected HIGH/CRITICAL issues in sample Terraform code." 1
        echo "Tfsec output:"
        jq . "$TERRAFORM_INFRA_DIR/verify-tfsec.json"
    fi
    rm -f "$TERRAFORM_INFRA_DIR/verify-tfsec.json"
else
    echo "INFO: tfsec not found locally, skipping local tfsec execution check."
fi


# Final Summary
echo "------------------------------------------"
echo "Verification Summary:"
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo "------------------------------------------"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "❌ One or more verification checks failed for the CI/CD workflow."
  exit 1
else
  echo "✅✅✅ All CI/CD workflow verification checks passed (based on static analysis and local tool runs if available)."
  exit 0
fi

#!/usr/bin/env bash
# Deploy this week. Run from the week directory.
set -euo pipefail
cd "$(dirname "$0")/../terraform/environments/${ENV:-dev}"
terraform init
terraform plan -out=tfplan
echo
echo "Review the plan above. Press Enter to apply, Ctrl-C to abort."
read -r
terraform apply tfplan

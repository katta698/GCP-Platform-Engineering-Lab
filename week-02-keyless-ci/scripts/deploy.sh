#!/usr/bin/env bash
# Deploy this week. Run from the week directory.
#
# This is the last apply in the lab that runs from a human's credentials. It has
# to be: the identity it creates is the one every later apply uses, and that
# identity cannot create itself.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

terraform init
terraform plan -out=tfplan
echo
echo "Review the plan above. Press Enter to apply, Ctrl-C to abort."
read -r
terraform apply tfplan

#!/usr/bin/env bash
# Grant a role on the BILLING ACCOUNT, from the command line.
#
#   ./scripts/grant-billing-role.sh roles/billing.viewer
#   ./scripts/grant-billing-role.sh roles/billing.viewer user:someone@example.com
#
# Why this script exists
#
# A billing account sits outside the resource hierarchy and is owned by no
# project, so Terraform never manages its IAM in this lab — that is a standing
# rule, not an oversight. Grants on it are made by hand. "By hand" has until now
# meant the Cloud console, which is useless from a phone.
#
# Nothing about it actually requires a console. It requires a different
# IDENTITY. `roles/billing.admin` is held only by the personal Gmail account
# that created the billing account; the Workspace account the lab runs as holds
# costsManager and user, neither of which can grant anything. gcloud keeps
# multiple credentialed accounts side by side, so the fix is --account, not a
# browser.
#
# Verify both are present before assuming this will work:
#   gcloud auth list
#
# If the admin identity is missing, add it once with:
#   gcloud auth login katta.jayant@gmail.com
set -euo pipefail

ROLE="${1:?usage: $0 <role> [member]   e.g. $0 roles/billing.viewer}"
MEMBER="${2:-user:katta698@jayanthkatta.com}"
ADMIN_ACCOUNT="${BILLING_ADMIN_ACCOUNT:-katta.jayant@gmail.com}"

# The billing account ID is a secret and is never written into a committed file.
TFVARS="$(dirname "$0")/../terraform/bootstrap/terraform.tfvars"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(sed -n 's/^billing_account *= *"\([^"]*\)".*/\1/p' "$TFVARS")}"
: "${BILLING_ACCOUNT:?could not read billing_account; set BILLING_ACCOUNT explicitly}"

echo "== Checking the admin identity is available to gcloud =="
if ! gcloud auth list --format="value(account)" | grep -qx "$ADMIN_ACCOUNT"; then
  echo "  FAIL - ${ADMIN_ACCOUNT} is not authenticated."
  echo "         Run: gcloud auth login ${ADMIN_ACCOUNT}"
  exit 1
fi
echo "  OK - ${ADMIN_ACCOUNT} is present."
echo

echo "== Confirming it can actually grant =="
echo "   Checked rather than assumed: holding billing.admin is what carries"
echo "   setIamPolicy, and a lapsed token looks identical to a missing role"
echo "   until the write fails."
tok=$(gcloud auth print-access-token --account="$ADMIN_ACCOUNT" 2>/dev/null || true)
if [[ -z "$tok" ]]; then
  echo "  FAIL - could not mint a token for ${ADMIN_ACCOUNT} (credentials lapsed)."
  echo "         Run: gcloud auth login ${ADMIN_ACCOUNT}"
  exit 1
fi
held=$(curl -s -X POST -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
  "https://cloudbilling.googleapis.com/v1/billingAccounts/${BILLING_ACCOUNT}:testIamPermissions" \
  -d '{"permissions":["billing.accounts.setIamPolicy"]}' |
  grep -c "billing.accounts.setIamPolicy" || true)
if [[ "$held" -eq 0 ]]; then
  echo "  FAIL - ${ADMIN_ACCOUNT} does not hold billing.accounts.setIamPolicy."
  exit 1
fi
echo "  OK - setIamPolicy held."
echo

echo "== Granting ${ROLE} to ${MEMBER} =="
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
  --account="$ADMIN_ACCOUNT" \
  --member="$MEMBER" \
  --role="$ROLE" \
  >/dev/null
echo "  done."
echo

echo "== Verifying as the GRANTEE, not as the granter =="
echo "   A policy that contains the binding is not the same as a caller who can"
echo "   use it. This asks the account that needs the permission whether it now"
echo "   has it."
grantee="${MEMBER#user:}"
gtok=$(gcloud auth print-access-token --account="$grantee" 2>/dev/null || true)
if [[ -z "$gtok" ]]; then
  echo "  SKIP - ${grantee} is not authenticated locally; cannot verify as them."
  exit 0
fi
curl -s -X POST -H "Authorization: Bearer $gtok" -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${QUOTA_PROJECT:-katta698-gcp-lab-seed}" \
  "https://cloudbilling.googleapis.com/v1/billingAccounts/${BILLING_ACCOUNT}:testIamPermissions" \
  -d '{"permissions":["billing.accounts.getPricing","billing.accounts.updateUsageExportSpec"]}' |
  python -c "
import sys, json
held = set(json.load(sys.stdin).get('permissions', []))
need = {'billing.accounts.getPricing', 'billing.accounts.updateUsageExportSpec'}
for p in sorted(need):
    print(('  OK   ' if p in held else '  MISS ') + p)
print()
print('  Configuring a billing export needs BOTH.' if need - held else '  Export configuration unblocked.')
"

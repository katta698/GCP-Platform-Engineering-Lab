#!/usr/bin/env bash
# Verify what was actually deployed, independently of Terraform state.
#
#   ORG_ID=... SEED_PROJECT=... ./scripts/validate.sh
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
: "${SEED_PROJECT:?set SEED_PROJECT}"

echo "== Security baseline constraints enforced on the organization =="
echo "   Expect seven, including the two that make keys impossible."
gcloud org-policies list --organization="$ORG_ID"
echo

echo "== Workload identity pool =="
gcloud iam workload-identity-pools list \
  --project="$SEED_PROJECT" --location=global
echo

echo "== Provider, and the condition it enforces =="
echo "   attributeCondition is the line that matters. An empty one means this"
echo "   organization trusts every HCP Terraform user on the public issuer."
gcloud iam workload-identity-pools providers describe hcp-terraform-oidc \
  --project="$SEED_PROJECT" --location=global \
  --workload-identity-pool=hcp-terraform \
  --format="yaml(state,oidc.issuerUri,attributeCondition,attributeMapping)"
echo

echo "== Service accounts =="
gcloud iam service-accounts list --project="$SEED_PROJECT"
echo

echo "== Who may impersonate the apply account =="
echo "   The member must be a principalSet scoped to the apply run phase."
gcloud iam service-accounts get-iam-policy \
  "tf-apply@${SEED_PROJECT}.iam.gserviceaccount.com" \
  --project="$SEED_PROJECT" --format=yaml
echo

echo "== Proof that the plan identity cannot write =="
echo "   Roles held at the organization by each account."
for sa in tf-plan tf-apply; do
  echo "--- ${sa}"
  gcloud organizations get-iam-policy "$ORG_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:${sa}@${SEED_PROJECT}.iam.gserviceaccount.com" \
    --format="value(bindings.role)"
done
echo

echo "== The shortcut, attempted =="
echo "   This must FAIL. If a key file appears, the baseline is not enforced"
echo "   and every claim this week makes is wrong."
if gcloud iam service-accounts keys create /dev/null \
     --iam-account="tf-apply@${SEED_PROJECT}.iam.gserviceaccount.com" \
     --project="$SEED_PROJECT" 2>&1 | tee /dev/stderr | grep -qi "denied\|violat\|constraint"; then
  echo "OK — key creation denied by organization policy."
else
  echo "FAIL — key creation was not denied. Stop and investigate."
  exit 1
fi

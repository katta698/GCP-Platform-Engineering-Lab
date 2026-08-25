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
echo "   This must FAIL. If a key is created, the baseline is not enforced and"
echo "   every claim this week makes is wrong."
SA="tf-apply@${SEED_PROJECT}.iam.gserviceaccount.com"

# Count keys before. USER_MANAGED only: every service account carries
# Google-managed keys it did not ask for, and counting those would report a
# failure on a working system.
keys_before=$(gcloud iam service-accounts keys list --iam-account="$SA"   --project="$SEED_PROJECT" --managed-by=user --format="value(name)" | wc -l)

# The output path is a real file, not /dev/null. If the constraint were somehow
# not enforced, a discarded key would still EXIST server-side — an unaccounted
# credential on the identity that can change the estate, created by the very
# test meant to prove none can exist. Better to hold it, notice it, and delete it.
tmpkey="$(mktemp -t sa-key-XXXXXX.json)"
set +e
gcloud iam service-accounts keys create "$tmpkey"   --iam-account="$SA" --project="$SEED_PROJECT" 2>"$tmpkey.err"
rc=$?
set -e
cat "$tmpkey.err" >&2

keys_after=$(gcloud iam service-accounts keys list --iam-account="$SA"   --project="$SEED_PROJECT" --managed-by=user --format="value(name)" | wc -l)

# The assertion is on state, not on wording. Matching the error text would turn
# a reworded gcloud message into a silent pass.
if [[ "$rc" -ne 0 && "$keys_after" -eq "$keys_before" ]]; then
  echo "OK - key creation refused, and no key exists that did not before."
  shred -u "$tmpkey" 2>/dev/null || rm -f "$tmpkey"
  rm -f "$tmpkey.err"
else
  echo "FAIL - a user-managed key was created. The baseline is not enforced."
  echo "       Deleting it now, then stopping."
  gcloud iam service-accounts keys list --iam-account="$SA"     --project="$SEED_PROJECT" --managed-by=user --format="value(name)"     | while read -r k; do
        gcloud iam service-accounts keys delete "$k" --iam-account="$SA"           --project="$SEED_PROJECT" --quiet || true
      done
  shred -u "$tmpkey" 2>/dev/null || rm -f "$tmpkey"
  rm -f "$tmpkey.err"
  exit 1
fi

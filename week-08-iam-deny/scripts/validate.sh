#!/usr/bin/env bash
# Verify Week 08 against GCP, independently of Terraform state.
#
#   ORG_ID=... ./scripts/validate.sh
#
# Everything here asks Policy Troubleshooter v3, never v1 and never
# `gcloud policy-troubleshoot iam`. v1 evaluates ALLOW policies only: with a
# deny policy actively blocking the permission, it answered GRANTED. A check
# built on it would pass while the control it is checking does nothing.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
SEED="${SEED_PROJECT:-katta698-gcp-lab-seed}"
PLAN="${PLAN_SA:-tf-plan@katta698-gcp-lab-seed.iam.gserviceaccount.com}"
APPLY="${APPLY_SA:-tf-apply@katta698-gcp-lab-seed.iam.gserviceaccount.com}"
ORG_RES="//cloudresourcemanager.googleapis.com/organizations/${ORG_ID}"

# overall access state for one principal/permission pair
access() {
  curl -s -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: ${SEED}" \
    -H "Content-Type: application/json" \
    "https://policytroubleshooter.googleapis.com/v3/iam:troubleshoot" \
    -d "{\"accessTuple\":{\"principal\":\"$1\",\"fullResourceName\":\"${ORG_RES}\",\"permission\":\"$2\"}}" |
    python -c "import sys,json; print(json.load(sys.stdin).get('overallAccessState','UNKNOWN'))"
}

expect() { # principal permission expected label
  got=$(access "$1" "$2")
  if [[ "$got" == "$3" ]]; then
    echo "  OK   $4 -> $got"
  else
    echo "  FAIL $4 -> $got (expected $3)"
    exit 1
  fi
}

echo "== The fix: a custom role carrying only what a plan reads =="
perms=$(gcloud iam roles describe tfPlanAssetReader --organization="$ORG_ID" \
  --format="value(includedPermissions)" 2>/dev/null | tr ';' '\n' | sort | tr '\n' ' ')
if [[ "$perms" == *"cloudasset.feeds.get"* && "$perms" == *"cloudasset.feeds.list"* ]]; then
  echo "  OK - tfPlanAssetReader: ${perms}"
  extra=$(tr ' ' '\n' <<<"$perms" | grep -vcE "^(cloudasset.feeds.get|cloudasset.feeds.list|)$" || true)
  [[ "$extra" -eq 0 ]] && echo "       and nothing else." || echo "       NOTE: ${extra} extra permission(s) - least privilege has drifted."
else
  echo "  FAIL - custom role missing or wrong: ${perms:-none}"
  exit 1
fi
echo

echo "== The over-grant is gone =="
echo "   Week 07 gave the read-only identity roles/cloudasset.owner because no"
echo "   predefined role could read a feed without also deleting one."
if gcloud organizations get-iam-policy "$ORG_ID" --flatten="bindings[].members" \
     --filter="bindings.members~tf-plan AND bindings.role=roles/cloudasset.owner" \
     --format="value(bindings.role)" 2>/dev/null | grep -q cloudasset.owner; then
  echo "  FAIL - tf-plan still holds roles/cloudasset.owner."
  exit 1
fi
echo "  OK - tf-plan no longer holds it."
echo

echo "== The guardrail exists, and exempts the right two =="
# Read over IAM v2 REST, not `gcloud iam policies describe`: the gcloud form
# returned nothing for an org attachment point, and the list endpoint returns
# names without rules. The GET is the only call that shows the exceptions,
# which are the part worth checking.
AP="cloudresourcemanager.googleapis.com%2Forganizations%2F${ORG_ID}"
deny=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)"   -H "x-goog-user-project: ${SEED}"   "https://iam.googleapis.com/v2/policies/${AP}/denypolicies/deny-asset-feed-deletion")

if grep -q "feeds.delete" <<<"$deny"; then
  echo "  OK - deny-asset-feed-deletion denies cloudasset.googleapis.com/feeds.delete"
  grep -q "serviceAccounts/tf-apply" <<<"$deny" && echo "       exempts tf-apply (it manages the feed)"     || { echo "  FAIL - tf-apply not exempt; Week 07 becomes undeployable."; exit 1; }
  grep -q "goog/subject" <<<"$deny" && echo "       exempts a break-glass human"     || { echo "  FAIL - no break-glass exception. A deny with no way out gets deleted under pressure."; exit 1; }
else
  echo "  FAIL - deny policy missing or unreadable."
  exit 1
fi
echo

echo "== What the three principals can actually do (Troubleshooter v3) =="
expect "$PLAN"  cloudasset.feeds.delete CANNOT_ACCESS "tf-plan  may NOT delete a feed"
expect "$PLAN"  cloudasset.feeds.get    CAN_ACCESS    "tf-plan  may still read one"
expect "$APPLY" cloudasset.feeds.delete CAN_ACCESS    "tf-apply may still manage one"
echo

echo "== The instrument check =="
echo "   Kept as a demonstration, not a test. In THIS state both agree, because"
echo "   the custom role means the permission is not granted in the first place."
echo "   They diverge the moment someone re-grants a broad role: v1 then reports"
echo "   GRANTED while the deny policy is actively blocking. Measured 2026-10-05."
v1=$(curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: ${SEED}" -H "Content-Type: application/json" \
  "https://policytroubleshooter.googleapis.com/v1/iam:troubleshoot" \
  -d "{\"accessTuple\":{\"principal\":\"${PLAN}\",\"fullResourceName\":\"${ORG_RES}\",\"permission\":\"cloudasset.feeds.delete\"}}" |
  python -c "import sys,json; print(json.load(sys.stdin).get('access','UNKNOWN'))")
echo "  v1 says: ${v1}   (allow policies only - it can never see a deny)"
echo "  v3 says: $(access "$PLAN" cloudasset.feeds.delete)"
echo "  Use v3. gcloud policy-troubleshoot iam calls v1."
echo

echo "All Week 08 checks passed."

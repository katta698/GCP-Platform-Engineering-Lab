#!/usr/bin/env bash
# Verify what was actually deployed, independently of Terraform state.
#
#   ORG_ID=... SEED_PROJECT=... DEV_FOLDER_ID=... ./scripts/validate.sh
#
# The distinction this script exists to make is SET versus DRY_RUN_SET. Both
# appear in the console as a policy on the constraint, and only one of them
# denies anything. A check that confirms "the policy exists" would pass
# identically against a week that enforces nothing.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
: "${SEED_PROJECT:?set SEED_PROJECT}"
: "${DEV_FOLDER_ID:?set DEV_FOLDER_ID — terraform output -raw dev_folder, digits only}"

# Four, not five. iam.managed.disableServiceAccountApiKeyCreation was dropped
# from this week once --effective showed it already enforced by a Google default.
# Listing it here would assert this configuration owns something it does not.
WEEK03_CONSTRAINTS=(
  compute.managed.requireOsLogin
  compute.managed.blockProjectSshKeys
  compute.managed.disableSerialPortAccess
  custom.requireTerraformLabelsOnBuckets
)

echo "== Every policy set on the organization =="
echo "   Expect eleven: seven inherited from Google's security baseline, and"
echo "   four added by this week. The BOOLEAN_POLICY column separates them —"
echo "   the baseline reads SET, this week's read DRY_RUN_SET until flipped."
echo
echo "   This list does NOT show constraints enforced by a Google default with"
echo "   no policy set. Use --effective for that; the console counts them and"
echo "   this command does not."
gcloud org-policies list --organization="$ORG_ID"
echo

echo "== This week's four, and the state of each =="
for c in "${WEEK03_CONSTRAINTS[@]}"; do
  spec=$(gcloud org-policies describe "$c" --organization="$ORG_ID" \
    --format="value(spec.rules[0].enforce)" 2>/dev/null || true)
  dry=$(gcloud org-policies describe "$c" --organization="$ORG_ID" \
    --format="value(dryRunSpec.rules[0].enforce)" 2>/dev/null || true)

  if [[ -n "$spec" ]]; then
    echo "  ENFORCED   ${c}  (spec.enforce=${spec})"
  elif [[ -n "$dry" ]]; then
    echo "  dry-run    ${c}  (dryRunSpec.enforce=${dry}) — logs, denies nothing"
  else
    echo "  MISSING    ${c} — not set at all"
    exit 1
  fi
done
echo

echo "== The custom constraint's definition =="
echo "   A custom constraint can exist while enforcing nothing: defining it only"
echo "   makes the name available. The policy above is what activates it."
gcloud org-policies describe-custom-constraint \
  custom.requireTerraformLabelsOnBuckets \
  --organization="$ORG_ID" \
  --format="yaml(actionType,methodTypes,resourceTypes,condition)"
echo

echo "== The deliberate exception at workloads/dev =="
echo "   The organization refuses serial console access. This folder does not."
echo "   A policy closest to the resource wins, so this overrides the org's."
dev_spec=$(gcloud org-policies describe compute.managed.disableSerialPortAccess \
  --folder="$DEV_FOLDER_ID" --format="value(spec.rules[0].enforce)" 2>/dev/null || true)

# gcloud renders booleans Python-style — "True"/"False", not the "TRUE"/"FALSE"
# the API and the Terraform config use. Comparing against the API spelling makes
# this check fail on a correct deployment, and makes the enforced check below
# silently take the dry-run branch and pass for the wrong reason. Lowercase both.
if [[ "${dev_spec,,}" == "false" ]]; then
  echo "  OK - dev overrides the organization with enforce=FALSE."
else
  echo "  FAIL - expected enforce=FALSE at the dev folder, got '${dev_spec:-nothing}'."
  echo "         Without this the exception is not in place and the week's"
  echo "         inheritance claim is unproven."
  exit 1
fi
echo

echo "== The constraint, tested against a real request =="
echo
# Enforcement lags the policy write. Measured 2026-09-03: an unlabelled bucket
# was still being created a minute after the flip, with describe --effective
# already reporting enforce: true, and was refused about two minutes later.
# Without this wait the script reports a working constraint as broken, which
# sends the reader editing correct code.
if [[ "$(gcloud org-policies describe custom.requireTerraformLabelsOnBuckets       --organization="$ORG_ID" --format="value(spec.rules[0].enforce)" 2>/dev/null)" =~ ^[Tt]rue$ ]]; then
  echo "   Waiting 120s: enforcement lags the policy write."
  sleep 120
fi
# Which behaviour is correct depends on whether the constraint is enforced yet,
# so the assertion is derived from the live policy rather than hardcoded. A test
# that assumes enforcement would fail every run made during the dry-run phase,
# and a test that assumes dry run would pass silently forever after the flip.
enforced=$(gcloud org-policies describe custom.requireTerraformLabelsOnBuckets \
  --organization="$ORG_ID" --format="value(spec.rules[0].enforce)" 2>/dev/null || true)

BUCKET="wk03-validate-$(date +%s)"
set +e
out=$(gcloud storage buckets create "gs://${BUCKET}" \
  --project="$SEED_PROJECT" --location=us-central1 \
  --uniform-bucket-level-access 2>&1)
rc=$?
set -e

# Always clean up, whichever way it went. A validation script that leaves
# storage behind is a validation script that quietly grows a bill.
if [[ $rc -eq 0 ]]; then
  gcloud storage rm --recursive "gs://${BUCKET}" --quiet >/dev/null 2>&1 || true
fi

if [[ "${enforced,,}" == "true" ]]; then
  echo "   Constraint is ENFORCED. An unlabelled bucket must be refused."
  if [[ $rc -ne 0 ]] && grep -qi "constraint\|orgpolicy\|violates" <<<"$out"; then
    echo "  OK - refused, and refused by the constraint:"
    grep -i "constraint\|violates" <<<"$out" | head -2 | sed 's/^/       /'
  else
    echo "  FAIL - an unlabelled bucket was created while the constraint is enforced."
    echo "$out" | head -5 | sed 's/^/       /'
    exit 1
  fi
else
  echo "   Constraint is in DRY RUN. An unlabelled bucket must be ALLOWED,"
  echo "   and the violation logged. Denial here would mean it is enforced."
  if [[ $rc -eq 0 ]]; then
    echo "  OK - allowed, as dry run requires. Now the violation record:"
    # Queried against the PROJECT, not the organization. The policy is set at the
    # organization; the audit entry is written where the request was served.
    # Reading the org for a policy log stream returns nothing AND no error, which
    # is indistinguishable from "there were no violations".
    sleep 20 # the entry is not written synchronously with the response
    found=$(gcloud logging read \
      'protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata" AND protoPayload.resourceName:"'"${BUCKET}"'"' \
      --project="$SEED_PROJECT" --limit=1 --freshness=10m \
      --format="value(protoPayload.metadata.dryRunResult,protoPayload.metadata.liveResult)" 2>/dev/null || true)

    if [[ "$found" == *"DENIED"* && "$found" == *"ALLOWED"* ]]; then
      echo "  OK - dryRunResult=DENIED, liveResult=ALLOWED."
      echo "       The rule would have refused it, and did not. That pair is the"
      echo "       evidence needed before enforcing it."
    else
      echo "  WARN - no dry-run violation record found for ${BUCKET}."
      echo "         Log delivery can lag; re-check by hand before concluding the"
      echo "         constraint is not evaluating:"
      echo "         gcloud logging read 'protoPayload.metadata.\"@type\"=\"type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata\"' --project=\$SEED_PROJECT --freshness=2h"
    fi
  else
    echo "  FAIL - refused while only a dry-run spec is set."
    echo "$out" | head -5 | sed 's/^/       /'
    exit 1
  fi
fi

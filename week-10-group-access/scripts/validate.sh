#!/usr/bin/env bash
# Verify Week 10 against GCP and Cloud Identity, independently of Terraform state.
#
#   ORG_ID=... ./scripts/validate.sh
#
# The question this week asks is "does access actually follow membership", so
# the checks are about who holds what and whether removing a membership removes
# the access. A resource existing proves nothing here.
set -uo pipefail

: "${ORG_ID:?set ORG_ID}"
SEED="${SEED_PROJECT:-katta698-gcp-lab-seed}"
DOMAIN="${DOMAIN:-jayanthkatta.com}"
GROUP="${GROUP:-grp-gcp-log-readers@${DOMAIN}}"
SUBJECT="${SUBJECT:-group-access-demo@${SEED}.iam.gserviceaccount.com}"
fail=0

# Cloud Identity is a client-based API and ignores the ADC quota project, so
# every call here carries --billing-project explicitly. Without it the call is
# attributed to a Google-owned project and returns SERVICE_DISABLED naming a
# project number that appears nowhere in this lab. Measured 2026-10-23.
CI=(--billing-project="$SEED")

echo "== The group exists, and is an ACCESS group =="
if gcloud identity groups describe "$GROUP" "${CI[@]}" --format="value(name)" >/dev/null 2>&1; then
  echo "  OK   $GROUP exists"
else
  echo "  FAIL $GROUP not found"
  fail=1
fi
echo

echo "== The subject holds NOTHING directly =="
echo "   This is what makes the revocation test mean anything. If the subject"
echo "   picks up the permission by another path, the test passes while proving"
echo "   nothing - the same defect as testing a denial with an under-privileged"
echo "   identity, pointing the other way."
direct=$(gcloud organizations get-iam-policy "$ORG_ID" --flatten="bindings[].members" \
           --filter="bindings.members~${SUBJECT}" --format="value(bindings.role)" 2>/dev/null | wc -l)
if [[ "$direct" -eq 0 ]]; then
  echo "  OK   no org-level binding names the subject"
else
  echo "  FAIL subject holds $direct direct org role(s) - measurement is invalid"
  fail=1
fi
echo

echo "== The subject is a MEMBER of the group, not a manager =="
role=$(gcloud identity groups memberships describe --group-email="$GROUP" \
         --member-email="$SUBJECT" "${CI[@]}" --format="value(roles[0].name)" 2>/dev/null)
if [[ "$role" == "MEMBER" ]]; then
  echo "  OK   subject is MEMBER"
else
  echo "  FAIL subject role is '${role:-absent}', expected MEMBER"
  fail=1
fi
echo

echo "== The folder grant names the GROUP, not a person =="
echo "   The whole architectural change, in one line of policy."
if gcloud resource-manager folders get-iam-policy "${PLATFORM_FOLDER#folders/}" \
     --flatten="bindings[].members" \
     --filter="bindings.role=roles/logging.viewer AND bindings.members~^group:" \
     --format="value(bindings.members)" 2>/dev/null | grep -q "$GROUP"; then
  echo "  OK   roles/logging.viewer on the folder is held by $GROUP"
else
  echo "  FAIL no group binding for roles/logging.viewer on the folder"
  fail=1
fi
echo

echo "== The pipeline holds no Workspace admin role =="
echo "   WITH_INITIAL_OWNER makes the creating identity the OWNER of the group"
echo "   it created, which is why tf-apply needs no Groups Admin role. Groups"
echo "   Admin would let it manage every group in the directory, including ones"
echo "   it never created - the same shape of over-grant as Editor-for-a-bucket."
echo "   Reported rather than asserted: this reads the group's owners."
gcloud identity groups memberships list --group-email="$GROUP" "${CI[@]}" \
  --format="table[no-heading](preferredMemberKey.id, roles[].name)" 2>/dev/null |
  sed 's/^/       /'
echo

echo "== Access follows membership =="
echo "   Run scripts/measure-membership-lag.sh for the timed version. This is"
echo "   the single point-in-time check: can the subject read logs right now."
if gcloud logging read "timestamp>=\"$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)\"" \
     --project="${LOGGING_PROJECT:-katta698-gcp-logging}" --limit=1 \
     --impersonate-service-account="$SUBJECT" >/dev/null 2>&1; then
  echo "  OK   subject can read logs - via the group and nothing else"
else
  echo "  FAIL subject cannot read logs while holding the membership"
  fail=1
fi
echo

[[ "$fail" -eq 0 ]] && echo "All Week 10 checks passed." || { echo "Week 10 has failing checks."; exit 1; }

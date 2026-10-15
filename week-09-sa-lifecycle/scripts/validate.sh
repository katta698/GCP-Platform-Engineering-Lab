#!/usr/bin/env bash
# Verify Week 09 against GCP, independently of Terraform state.
#
#   ORG_ID=... ./scripts/validate.sh
#
# The question this week asks is "should this identity still exist", so the
# checks are about usage and state, not about whether a resource was created.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
SEED="${SEED_PROJECT:-katta698-gcp-lab-seed}"
DISABLED_IN="${DISABLED_IN:-katta698-gcp-logging katta698-gcp-security}"

echo "== The unused default service accounts are disabled =="
echo "   Disabled, never deleted. The email of a deleted service account can be"
echo "   reused, but IAM tracks an internal unique ID - so role bindings that"
echo "   referred to the old one never apply to the replacement. A rebuild looks"
echo "   identical and is not. Disable is reversible in one field."
fail=0
for P in $DISABLED_IN; do
  line=$(gcloud iam service-accounts list --project="$P" \
           --filter="email~compute@developer" --format="value(email,disabled)" 2>/dev/null || true)
  state=$(awk '{print $2}' <<<"$line")
  if [[ "$state" == "True" ]]; then
    echo "  OK   $P - default compute SA disabled"
  else
    echo "  FAIL $P - default compute SA is not disabled (state: ${state:-not found})"
    fail=1
  fi
done
[[ "$fail" -eq 0 ]] || exit 1
echo

echo "== They are still disabled, not deleted =="
echo "   A deleted account would not appear at all. Presence is the check."
for P in $DISABLED_IN; do
  n=$(gcloud iam service-accounts list --project="$P" --filter="email~compute@developer" \
        --format="value(email)" 2>/dev/null | wc -l)
  [[ "$n" -ge 1 ]] && echo "  OK   $P - account still exists (recoverable)" \
                   || { echo "  FAIL $P - account is gone, not merely disabled"; exit 1; }
done
echo

echo "== Key creation is blocked on BOTH constraint generations =="
echo "   This is the week's trap. Google's baseline enforces the MANAGED"
echo "   constraint; the legacy one of the same name had no policy and therefore"
echo "   read enforce:false. Checking only that one produces a confident, wrong"
echo "   conclusion that the rule is off - which is exactly what happened while"
echo "   planning this week."
for C in iam.disableServiceAccountKeyCreation iam.managed.disableServiceAccountKeyCreation; do
  e=$(gcloud org-policies describe "$C" --organization="$ORG_ID" --effective \
        --format="value(spec.rules[0].enforce)" 2>/dev/null || echo "")
  if [[ "$e" == "True" ]]; then
    echo "  OK   $C enforced"
  else
    echo "  FAIL $C is NOT enforced (got: ${e:-none})"
    exit 1
  fi
done
echo

echo "== No user-managed keys exist anywhere =="
echo "   The constraint stops new ones. This asks whether any already existed."
total=0
for P in $(gcloud projects list --format="value(projectId)" 2>/dev/null); do
  for SA in $(gcloud iam service-accounts list --project="$P" --format="value(email)" 2>/dev/null); do
    k=$(gcloud iam service-accounts keys list --iam-account="$SA" --managed-by=user \
          --format="value(name)" 2>/dev/null | wc -l)
    if [[ "$k" -gt 0 ]]; then echo "  FAIL $SA holds $k user-managed key(s)"; total=$((total+k)); fi
  done
done
[[ "$total" -eq 0 ]] && echo "  OK - zero user-managed keys org-wide." || exit 1
echo

echo "== The accounts we kept are the ones still in use =="
echo "   Reported rather than asserted: an account idle today may be seasonal,"
echo "   and a check that fails on that would train people to ignore it."
gcloud policy-intelligence query-activity --activity-type=serviceAccountLastAuthentication \
  --project="$SEED" --format=json 2>/dev/null | python -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit()
for a in d:
    sa = a.get('fullResourceName','').split('/')[-1]
    t = (a.get('activity') or {}).get('lastAuthenticatedTime') or 'NEVER'
    print(f'       {sa:54} {t}')
"
echo

echo "All Week 09 checks passed."

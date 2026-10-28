#!/usr/bin/env bash
#
# Week 11 — Just-in-time privileged access.
#
# Checks 1-5 run against a deployed entitlement with NO grant active, and are
# the premise: the subject holds nothing, the folder policy carries no binding
# for it, and the command the week turns on is refused.
#
# Check 6 is the week itself and cannot be automated end to end, because a human
# has to approve the grant. Run request-grant.sh, approve in the console, then
# re-run with GRANT_ACTIVE=1.
#
# Usage:
#   ORG_ID=... PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... ./scripts/validate.sh
#   GRANT_ACTIVE=1 ... ./scripts/validate.sh
#
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
: "${PLATFORM_FOLDER_ID:?set PLATFORM_FOLDER_ID}"
: "${SEED_PROJECT_ID:?set SEED_PROJECT_ID}"

# Week 10's validate.sh died here under `set -u` on an unset folder variable, so
# every input this script needs is asserted above rather than defaulted below.
GRANT_ACTIVE="${GRANT_ACTIVE:-0}"
ENTITLEMENT_ID="folder-security-review"
SUBJECT="jit-access-demo@${SEED_PROJECT_ID}.iam.gserviceaccount.com"
ELEVATED_ROLE="${ELEVATED_ROLE:-roles/iam.securityReviewer}"

fail=0
ok()   { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }
note() { echo "       $*"; }

echo "== 1. The API is enabled =="
if gcloud services list --project="$SEED_PROJECT_ID" --format='value(config.name)' \
     | grep -q '^privilegedaccessmanager.googleapis.com$'; then
  ok "privilegedaccessmanager.googleapis.com enabled"
else
  bad "privilegedaccessmanager.googleapis.com not enabled"
fi

echo
echo "== 2. The entitlement exists, and is a template rather than a grant =="
ENT_JSON="$(gcloud pam entitlements describe "$ENTITLEMENT_ID" \
  --folder="$PLATFORM_FOLDER_ID" --location=global --format=json 2>/dev/null || echo '{}')"

if [[ "$(echo "$ENT_JSON" | python -c 'import json,sys; print(bool(json.load(sys.stdin)))')" == "True" ]]; then
  ok "entitlement $ENTITLEMENT_ID present on folders/$PLATFORM_FOLDER_ID"

  CHECK_PY="$(mktemp)"
  cat > "$CHECK_PY" <<'PY'
import json, sys
role = sys.argv[1]
e = json.load(sys.stdin)
dur = e.get("maxRequestDuration", "")
print(f"       max request duration: {dur}")
if dur != "1800s":
    print(f"       note: not the documented minimum (1800s)")
roles = [rb.get("role") for rb in
         e.get("privilegedAccess", {}).get("gcpIamAccess", {}).get("roleBindings", [])]
print(f"       grants: {', '.join(roles) or '(none)'}")
if role not in roles:
    print(f"  FAIL entitlement does not grant {role}")
    raise SystemExit(1)

elig = set()
for u in e.get("eligibleUsers", []):
    elig.update(u.get("principals", []))
appr = set()
for step in (e.get("approvalWorkflow", {}).get("manualApprovals", {}).get("steps", [])):
    for a in step.get("approvers", []):
        appr.update(a.get("principals", []))
print(f"       eligible: {', '.join(sorted(elig)) or '(none)'}")
print(f"       approvers: {len(appr)} principal(s)")

# The control this week rests on. If one principal can both request and
# approve, the approval step is a form filled in twice.
if elig & appr:
    print("  FAIL requester and approver overlap - the approval proves nothing")
    raise SystemExit(1)
print("  ok   requester and approver are different principals")
PY
  if ! python "$CHECK_PY" "$ELEVATED_ROLE" <<<"$ENT_JSON"; then fail=1; fi
  rm -f "$CHECK_PY"
else
  bad "entitlement $ENTITLEMENT_ID not found"
fi

echo
echo "== 3. The subject holds nothing directly =="
# The premise of the whole measurement. Any direct binding anywhere in the
# hierarchy gives the subject another route to the permission and the
# before/after stops meaning anything.
DIRECT="$(gcloud organizations get-iam-policy "$ORG_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.members:${SUBJECT}" \
  --format='value(bindings.role)' 2>/dev/null | tr '\n' ' ')"
FOLDER_DIRECT="$(gcloud resource-manager folders get-iam-policy "$PLATFORM_FOLDER_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.members:${SUBJECT}" \
  --format='value(bindings.role)' 2>/dev/null | tr '\n' ' ')"

if [[ -z "${DIRECT// }" ]]; then
  ok "no organization-level binding names the subject"
else
  bad "subject holds organization roles: $DIRECT"
fi

echo
echo "== 4. The folder policy reflects grant state, not configuration =="
if [[ "$GRANT_ACTIVE" == "1" ]]; then
  if [[ -n "${FOLDER_DIRECT// }" ]]; then
    ok "grant active: folder policy carries $FOLDER_DIRECT for the subject"
    note "written by PAM, not by Terraform - nothing in main.tf creates this binding"
  else
    bad "grant reported active but no binding is present on the folder"
  fi
else
  if [[ -z "${FOLDER_DIRECT// }" ]]; then
    ok "no grant active: folder policy carries no binding for the subject"
  else
    bad "no grant active, yet the folder policy carries $FOLDER_DIRECT"
  fi
fi

echo
echo "== 5. The access itself, as the subject =="
# Impersonate rather than run as the operator. The operator holds
# organizationAdmin, so this command would succeed for them whatever the
# entitlement says, and the result would prove nothing.
set +e
OUT="$(gcloud resource-manager folders get-iam-policy "$PLATFORM_FOLDER_ID" \
  --impersonate-service-account="$SUBJECT" --format=json 2>&1)"
RC=$?
set -e

if [[ "$GRANT_ACTIVE" == "1" ]]; then
  if [[ $RC -eq 0 ]]; then
    ok "permitted while the grant is active"
  else
    bad "grant active but the read was refused"
    note "$(echo "$OUT" | head -2)"
  fi
else
  if [[ $RC -ne 0 ]] && grep -qi 'PERMISSION_DENIED\|does not have permission' <<<"$OUT"; then
    ok "refused with no grant active"
    note "$(grep -oi 'PERMISSION_DENIED[^\"]*' <<<"$OUT" | head -1)"
  elif [[ $RC -eq 0 ]]; then
    bad "the subject could read the folder policy with NO grant active"
    note "something grants it this role by another path; check 3 should have caught it"
  else
    bad "refused, but not with PERMISSION_DENIED - the denial may be for the wrong reason"
    note "$(echo "$OUT" | head -2)"
  fi
fi

echo
echo "== 6. Grants, past and present =="
gcloud pam grants list --entitlement="$ENTITLEMENT_ID" \
  --folder="$PLATFORM_FOLDER_ID" --location=global \
  --format='table(name.basename(),state,requestedDuration,createTime)' 2>/dev/null \
  || note "no grants yet - run scripts/request-grant.sh"

echo
if [[ $fail -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "All checks passed (GRANT_ACTIVE=$GRANT_ACTIVE)."

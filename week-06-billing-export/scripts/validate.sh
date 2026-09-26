#!/usr/bin/env bash
# Verify Week 06 against GCP, independently of Terraform state.
#
#   BILLING_ACCOUNT=... DATA_PROJECT=... SEED_PROJECT=... ./scripts/validate.sh
#
# The point of this week is a queryable record of spend, so the checks ask the
# data what it contains rather than asking Terraform what it created. A dataset
# that exists and holds nothing is a passing resource and a failing export.
set -euo pipefail

: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT}"
: "${DATA_PROJECT:?set DATA_PROJECT}"
: "${SEED_PROJECT:?set SEED_PROJECT}"

TOPIC="projects/${DATA_PROJECT}/topics/billing-budget-notifications"
tok() { gcloud auth print-access-token; }
api() { curl -s -H "Authorization: Bearer $(tok)" -H "x-goog-user-project: ${SEED_PROJECT}" "$@"; }

echo "== The export that was already running =="
echo "   Checked before anything else because this week's premise was wrong"
echo "   about it. The table is in the seed project, not the data project."
# The table name carries the billing account ID, so it is derived rather than
# written down - this file is committed and that ID is not.
tbl=$(bq ls --project_id="$SEED_PROJECT" --format=json billing_export 2>/dev/null |
  python -c "
import sys,json
d=json.load(sys.stdin)
print(d[0]['tableReference']['tableId'] if d else '')
" || true)
if [[ -n "$tbl" ]]; then
  echo "  OK - export table present in ${SEED_PROJECT}.billing_export"
else
  echo "  FAIL - no export tables found. The console link is gone or never made."
  exit 1
fi
echo

echo "== Does it actually answer the cost question? =="
echo "   Every week of this lab opens with a cost note. This is the query that"
echo "   makes those numbers checkable rather than asserted."
bq query --use_legacy_sql=false --project_id="$SEED_PROJECT" --format=pretty \
  "SELECT COUNT(*) AS rows_, MIN(DATE(usage_start_time)) AS first_day,
          MAX(DATE(usage_start_time)) AS last_day, ROUND(SUM(cost),4) AS total_cost,
          COUNT(DISTINCT project.id) AS projects
   FROM \`${SEED_PROJECT}.billing_export.${tbl}\`" 2>/dev/null
echo

echo "== The pricing dataset =="
if bq ls --project_id="$DATA_PROJECT" 2>/dev/null | grep -q billing_pricing; then
  echo "  OK - ${DATA_PROJECT}.billing_pricing exists."
  if bq ls --project_id="$DATA_PROJECT" billing_pricing 2>/dev/null | grep -q cloud_pricing_export; then
    echo "       and is receiving data."
  else
    echo "       EMPTY - the console link is not made yet, or is inside the 48h"
    echo "       first-delivery window. See Outstanding in the README: the"
    echo "       operating account lacks billing.accounts.getPricing."
  fi
else
  echo "  FAIL - pricing dataset missing."
  exit 1
fi
echo

echo "== The budget's notification path =="
echo "   Asks the budget what it is attached to. A topic that exists proves"
echo "   nothing; the budget has to name it."
attached=$(api "https://billingbudgets.googleapis.com/v1/billingAccounts/${BILLING_ACCOUNT}/budgets" |
  python -c "
import sys,json
d=json.load(sys.stdin)
for b in d.get('budgets',[]):
    t=b.get('notificationsRule',{}).get('pubsubTopic')
    if t: print(t)
" || true)
if grep -qx "$TOPIC" <<<"$attached"; then
  echo "  OK - budget publishes to ${TOPIC}"
else
  echo "  FAIL - no budget names that topic. Attached topics were: ${attached:-none}"
  exit 1
fi
echo

echo "== Who Google publishes as =="
echo "   Read back rather than asserted. This lab guessed this address once and"
echo "   guessed wrong, so the check is that SOMETHING holds publisher and then"
echo "   prints it, not that a hardcoded name matches."
pub=$(api "https://pubsub.googleapis.com/v1/${TOPIC}:getIamPolicy" |
  python -c "
import sys,json
d=json.load(sys.stdin)
for b in d.get('bindings',[]):
    if b.get('role')=='roles/pubsub.publisher':
        for m in b.get('members',[]): print(m)
" || true)
if [[ -n "$pub" ]]; then
  echo "  OK - roles/pubsub.publisher held by:"
  sed 's/^/       /' <<<"$pub"
else
  echo "  FAIL - nothing holds publisher on the topic. Cloud Billing's binding is"
  echo "         missing, which means notifications are silently not delivered."
  exit 1
fi
echo

echo "== The guardrail exception, and its blast radius =="
echo "   The override must apply to the data project and NOWHERE else. This is"
echo "   the check that would catch someone 'fixing' it at the organization."
# Read through the REST API with the seed project as the quota project, rather
# than `gcloud org-policies --project`. The latter needs the Organization Policy
# API enabled on the project being READ, which the data project has no other
# reason to enable - and when it is missing, gcloud answers with a prompt and a
# PERMISSION_DENIED that looks exactly like the policy being absent.
proj_rules=$(api "https://orgpolicy.googleapis.com/v2/projects/${DATA_PROJECT}/policies/iam.allowedPolicyMemberDomains" |
  python -c "
import sys,json
d=json.load(sys.stdin)
print(json.dumps(d.get('spec',{}).get('rules',[])))
" || true)
if grep -q "allowAll" <<<"$proj_rules"; then
  echo "  OK - ${DATA_PROJECT} overrides the inherited restriction."
else
  echo "  FAIL - no override on ${DATA_PROJECT}; budget notifications will"
  echo "         silently stop being delivered. rules were: ${proj_rules:-none}"
  exit 1
fi
echo
echo "  the organization must still be restricted:"
org_rules=$(gcloud org-policies describe iam.allowedPolicyMemberDomains \
  --organization="$(gcloud organizations list --format='value(ID)' | head -1)" \
  --effective --format="value(spec.rules)" 2>/dev/null || true)
if grep -q "allowAll" <<<"$org_rules"; then
  echo "  FAIL - domain restricted sharing is allow-all AT THE ORGANIZATION."
  echo "         The exception was meant to be one project wide."
  exit 1
else
  echo "  OK - organization still restricted to an allowed customer ID."
fi
echo

echo "All Week 06 checks passed."

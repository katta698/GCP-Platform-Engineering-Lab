#!/usr/bin/env bash
# Destroy everything Week 03 created.
#
#   ORG_ID=... ./scripts/cleanup.sh
#
# Week 03 costs nothing to leave running — it creates no billable resource, only
# organization policy. Teardown exists for correctness, not for cost.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"

cd "$(dirname "$0")/../terraform"

terraform destroy -input=false

# ---------------------------------------------------------------------------
# What destroy does NOT undo, stated rather than hoped
#
# 1. The two enabled APIs. Both google_project_service resources carry
#    disable_on_destroy = false, per this lab's convention, so orgpolicy and
#    logging stay enabled on the seed project. Deliberate: disabling an API that
#    another week may depend on is a far worse failure than leaving one on, and
#    an enabled API costs nothing.
#
# 2. roles/logging.viewer on the human identity. Granted out of band on
#    2026-09-03 so the dry-run violations could be read, and not managed by this
#    configuration — the same separation Week 02 applied to the billing grant.
#    Remove it by hand if you want the organization back exactly as it was:
#
#      gcloud organizations remove-iam-policy-binding "$ORG_ID" \
#        --member="user:katta698@jayanthkatta.com" --role="roles/logging.viewer"
#
# 3. The Google security baseline. Untouched by this week and untouched by this
#    teardown. Those seven constraints were never managed here.
# ---------------------------------------------------------------------------

echo
echo "== Verifying the teardown against GCP, not against state =="

# The custom constraint is the one worth checking by hand. Deleting a policy is
# ordinary; deleting a CUSTOM CONSTRAINT is where Google's own documentation
# contradicts itself — one page says the name can never be reused, another says
# it frees up within minutes. Which is true decides whether this script can
# honestly claim a clean teardown, so it is measured here rather than asserted.
remaining=$(gcloud org-policies list-custom-constraints --organization="$ORG_ID" \
  --format="value(name)" 2>/dev/null | grep -c "requireTerraformLabelsOnBuckets" || true)

if [[ "$remaining" -eq 0 ]]; then
  echo "  OK - custom constraint is gone."
  echo "       Whether the NAME can be reused immediately is a separate question."
  echo "       Re-running deploy.sh is the test; if it fails on a name conflict,"
  echo "       that is the answer and it belongs in the write-up."
else
  echo "  FAIL - custom constraint still present after destroy."
  exit 1
fi

echo
echo "== Policies still set on the organization =="
echo "   Expect seven: the inherited baseline, which this week never managed."
gcloud org-policies list --organization="$ORG_ID"

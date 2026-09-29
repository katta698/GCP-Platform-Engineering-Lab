#!/usr/bin/env bash
# Verify Week 07 against GCP, independently of Terraform state.
#
#   ORG_ID=... ./scripts/validate.sh
#
# An inventory is only worth having if it answers questions, so most of these
# checks are queries rather than existence tests. A dataset that exists and
# holds nothing passes a resource check and fails the only thing it is for.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
DATA_PROJECT="${DATA_PROJECT:-katta698-gcp-logging}"
SEED_PROJECT="${SEED_PROJECT:-katta698-gcp-lab-seed}"
TABLE="${DATA_PROJECT}.asset_inventory.hierarchy"

q() { bq query --use_legacy_sql=false --project_id="$SEED_PROJECT" --format=csv "$1" 2>/dev/null | tail -n +2; }

echo "== The feed exists and points at the topic =="
echo "   Advisory, not blocking, and the reason is the week's sharpest finding:"
echo "   roles/cloudasset.viewer does NOT carry cloudasset.feeds.get. Only"
echo "   roles/cloudasset.owner does, and that also grants create and delete."
echo "   An operator running this read-only genuinely cannot see a feed, so"
echo "   demanding it here would only teach people to over-grant themselves."
feed=$(gcloud asset feeds describe hierarchy-changes --organization="$ORG_ID" \
  --format="value(feedOutputConfig.pubsubDestination.topic)" 2>/dev/null || true)
if [[ "$feed" == *"asset-hierarchy-changes"* ]]; then
  echo "  OK - publishes to ${feed##*/}"
else
  echo "  SKIP - cannot read the feed as this identity. The publisher binding"
  echo "         checked below is what actually proves delivery works."
fi
echo

echo "== Cloud Asset Inventory can actually publish =="
echo "   CAI writes as ITSELF, not as the caller, so this binding is what makes"
echo "   the feed work. Read back rather than asserted; the address is derived"
echo "   from a project number and is easy to get subtly wrong."
pub=$(gcloud pubsub topics get-iam-policy "asset-hierarchy-changes" \
  --project="$DATA_PROJECT" --format=json 2>/dev/null |
  python -c "
import sys, json
d = json.load(sys.stdin)
for b in d.get('bindings', []):
    if b.get('role') == 'roles/pubsub.publisher':
        for m in b.get('members', []):
            print(m)
" || true)
if grep -q "gcp-sa-cloudasset" <<<"$pub"; then
  echo "  OK - $(sed 's/^/       /' <<<"$pub" | head -1 | sed 's/service-[0-9]*@/service-<PROJECT_NUMBER>@/')"
else
  echo "  FAIL - the asset service agent does not hold publisher. The feed will"
  echo "         silently stop delivering. Members were: ${pub:-none}"
  exit 1
fi
echo

echo "== The snapshot has rows, and they are recent =="
rows=$(q "SELECT COUNT(*) FROM \`${TABLE}\`" || echo 0)
if [[ "${rows:-0}" -gt 0 ]]; then
  echo "  OK - ${rows} assets in the snapshot"
  echo "  newest update_time: $(q "SELECT CAST(MAX(update_time) AS STRING) FROM \`${TABLE}\`")"
else
  echo "  FAIL - no rows. Run ./scripts/snapshot.sh first."
  exit 1
fi
echo

echo "== Audit: which projects are NOT in a folder =="
echo "   Week 05's custom constraint requires a folder parent and is still in"
echo "   dry run, so this reports rather than fails. A creation-time rule says"
echo "   nothing about what already exists - this is how you find out."
q "SELECT JSON_VALUE(resource.data, '\$.projectId')
   FROM \`${TABLE}\`
   WHERE asset_type = 'cloudresourcemanager.googleapis.com/Project'
     AND ARRAY_LENGTH(ancestors) = 2" | sed 's/^/       at the org root: /' || true
echo

echo "== Audit: user-managed service account keys =="
echo "   The lab's rule is none, ever. SYSTEM_MANAGED keys are Google's own"
echo "   signing keys and do not count - counting all keys reports 2 and looks"
echo "   like a breach."
bad=$(q "SELECT COUNT(*) FROM \`${TABLE}\`
         WHERE asset_type = 'iam.googleapis.com/ServiceAccountKey'
           AND JSON_VALUE(resource.data, '\$.keyType') = 'USER_MANAGED'" || echo 0)
if [[ "${bad:-0}" -eq 0 ]]; then
  echo "  OK - zero user-managed keys."
else
  echo "  FAIL - ${bad} user-managed key(s) exist. The keyless design has a hole."
  exit 1
fi
echo

echo "All Week 07 checks passed."

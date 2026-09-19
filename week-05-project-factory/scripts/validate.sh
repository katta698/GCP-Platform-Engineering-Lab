#!/usr/bin/env bash
# Verify Week 05 against GCP, independently of Terraform state.
#
#   ORG_ID=... PROJECT_ID=... ./scripts/validate.sh
#
# A factory is only worth having if you can show what it enforced. So this asks
# what the project actually CARRIES, not what the module was asked for — the
# two are the same only if the module worked.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
: "${PROJECT_ID:?set PROJECT_ID}"

echo "== The project the factory built =="
gcloud projects describe "$PROJECT_ID" \
  --format="table(projectId,lifecycleState,parent.type,parent.id)" 2>/dev/null
echo

echo "== Labels =="
echo "   week, env and managed-by are the lab's mandatory set. A project"
echo "   missing them is invisible in the billing export."
labels=$(gcloud projects describe "$PROJECT_ID" --format="value(labels)" 2>/dev/null || true)
echo "  $labels"
missing=""
for k in week env managed-by; do
  grep -q "${k}=" <<<"$labels" || missing="$missing $k"
done
if [[ -z "$missing" ]]; then
  echo "  OK - all three present."
  # goog-terraform-provisioned is added by the provider, not by the module.
  # Worth naming so nobody later "tidies it up" thinking it was a mistake.
  grep -q "goog-terraform-provisioned=true" <<<"$labels" &&
    echo "       (goog-terraform-provisioned is set by the provider, not by us)"
else
  echo "  FAIL - missing:$missing"
  exit 1
fi
echo

echo "== The environment tag =="
echo "   Not a label. Tags are IAM-controlled with closed values, and are the"
echo "   only one of the two an organization policy can scope on."
binding=$(gcloud resource-manager tags bindings list \
  --parent="//cloudresourcemanager.googleapis.com/projects/$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)" \
  --format="value(tagValue)" 2>/dev/null || true)
if [[ -n "$binding" ]]; then
  echo "  OK - bound: $binding"
else
  echo "  FAIL - no tag binding on the project."
  exit 1
fi
echo

echo "== Essential contacts =="
echo "   Google sends security bulletins and suspension notices here and"
echo "   nowhere else. A project with none fails silently, once, later."
contacts=$(gcloud essential-contacts list --project="$PROJECT_ID" \
  --format="value(notificationCategorySubscriptions)" 2>/dev/null || true)
if [[ -n "$contacts" ]]; then
  echo "  OK - subscribed to: $contacts"
else
  echo "  FAIL - no essential contact set."
  exit 1
fi
echo

echo "== No default network =="
echo "   auto_create_network = false is not a parameter of the module. A"
echo "   factory that lets a caller opt back into the permissive default VPC"
echo "   is a factory that will be asked to."
nets=$(gcloud compute networks list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
if [[ "$nets" -eq 0 ]]; then
  echo "  OK - no networks in the project."
else
  echo "  FAIL - $nets network(s) exist; the default network was created."
  exit 1
fi
echo

echo "== The naming constraint, and what it can actually read =="
echo "   Measured 2026-09-19 rather than read from documentation:"
echo "     resource.projectId    ACCEPTED"
echo "     resource.parent       ACCEPTED"
echo "     resource.labels       REJECTED"
echo "     resource.displayName  REJECTED"
echo "   So a custom constraint on a project cannot see that project's labels,"
echo "   and the constraint below enforces the two fields that exist."
gcloud org-policies describe-custom-constraint \
  custom.requireProjectNamingAndParent --organization="$ORG_ID" \
  --format="yaml(actionType,methodTypes,resourceTypes,condition)" 2>/dev/null
echo

spec=$(gcloud org-policies describe custom.requireProjectNamingAndParent \
  --organization="$ORG_ID" --format="value(spec.rules[0].enforce)" 2>/dev/null || true)
dry=$(gcloud org-policies describe custom.requireProjectNamingAndParent \
  --organization="$ORG_ID" --format="value(dryRunSpec.rules[0].enforce)" 2>/dev/null || true)

# Enforcement lags the write — measured at 75-100s in Week 03 and reproduced on
# a managed constraint in Week 04. Testing a constraint immediately after an
# apply reports a working control as broken.
if [[ -n "$spec" ]]; then
  echo "  ENFORCED (spec.enforce=$spec)"
  echo "  A project ID outside the standard would now be refused. Not tested"
  echo "  here: the billing account is at its project cap, so the probe would"
  echo "  fail on quota before the constraint ever evaluated it."
elif [[ -n "$dry" ]]; then
  echo "  dry-run (dryRunSpec.enforce=$dry) — evaluated and logged, denies nothing."
  echo "  Promote only after reading a violation:"
  echo "    gcloud logging read 'protoPayload.metadata.\"@type\"=\"type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata\"' --project=\$SEED_PROJECT --freshness=2h"
else
  echo "  FAIL - the constraint has neither a spec nor a dry-run spec."
  exit 1
fi

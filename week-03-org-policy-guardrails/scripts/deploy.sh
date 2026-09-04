#!/usr/bin/env bash
# Deploy Week 03.
#
#   ./scripts/deploy.sh
#
# Runs REMOTELY. This is the first week in the lab with no hand-run apply and no
# GCP credential on the machine that starts it: HCP Terraform mints an OIDC token
# per run, Google's STS exchanges it, and tf-apply — which already holds
# roles/orgpolicy.policyAdmin at the organization from Week 02 — does the writing.
#
# So there is nothing to authenticate here. If this fails on credentials, the
# problem is the workspace's TFC_GCP_* variables, not your gcloud session.
set -euo pipefail

cd "$(dirname "$0")/../terraform"

# Read what is already enforced BEFORE writing anything. Not a formality: this
# organization inherited seven constraints nobody in this lab chose, and a policy
# written at the organization on a constraint that is already set REPLACES the
# inherited spec rather than adding to it.
#
# Use --effective when you do. `gcloud org-policies list` shows only policies
# explicitly SET, and a managed constraint can be fully enforced by a Google
# default that appears in neither `list` nor plain `describe`. That is not
# hypothetical — it is how a constraint that was already enforced got added to
# this week as an "addition" and had to be removed again.
echo "Read current policy first:  ORG_ID=... ./scripts/read-current-policy.sh"
echo

terraform init -input=false
terraform apply -input=false

cat <<'NOTE'

Applied. Everything lands in DRY RUN, which is the intended end state of a first
deployment: each constraint is evaluated on every request and logged when it
would have denied, while denying nothing.

Do not flip anything to enforced yet. Read the violations first:

  gcloud logging read \
    'protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata"' \
    --project="$SEED_PROJECT" --freshness=2h

Then promote ONE constraint by adding it to the `enforce` map, and apply again.
One at a time is the whole point: flipping the set together loses the ability to
say which constraint an audit entry belonged to.
NOTE

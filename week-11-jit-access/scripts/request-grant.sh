#!/usr/bin/env bash
#
# Week 11 — request a grant against the entitlement, as the subject.
#
# Run AS THE SUBJECT, not as yourself. The operator holds organizationAdmin, so
# a grant requested and used by the operator proves nothing: the access would
# have worked without it. Impersonation is the only honest way to run this.
#
# The request lands in AWAITING_APPROVAL and stops there. A human approves it
# in the console - that separation is the control, and it is why this script
# cannot finish the job.
#
# Usage:
#   PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... ./scripts/request-grant.sh
#
set -euo pipefail

: "${PLATFORM_FOLDER_ID:?set PLATFORM_FOLDER_ID}"
: "${SEED_PROJECT_ID:?set SEED_PROJECT_ID}"

ENTITLEMENT_ID="folder-security-review"
SUBJECT="jit-access-demo@${SEED_PROJECT_ID}.iam.gserviceaccount.com"
DURATION="${DURATION:-1800s}"
REASON="${REASON:-Week 11 lab: demonstrating that elevated access expires on its own.}"

echo "Requesting a grant as ${SUBJECT}"
echo "  entitlement: ${ENTITLEMENT_ID} on folders/${PLATFORM_FOLDER_ID}"
echo "  duration:    ${DURATION}"
echo

gcloud pam grants create \
  --entitlement="$ENTITLEMENT_ID" \
  --folder="$PLATFORM_FOLDER_ID" \
  --location=global \
  --requested-duration="$DURATION" \
  --justification="$REASON" \
  --impersonate-service-account="$SUBJECT" \
  --format='value(name,state)'

echo
echo "Now, in order:"
echo "  1. CAPTURE FIGURE 04 WHILE IT IS STILL PENDING. The AWAITING_APPROVAL"
echo "     state is perishable - approving destroys it and it cannot be retaken"
echo "     without burning another 30-minute cycle."
echo "  2. Approve in the console as the operator."
echo "  3. GRANT_ACTIVE=1 ./scripts/validate.sh"
echo "  4. python scripts/measure-expiry-lag.py   (starts the clock)"

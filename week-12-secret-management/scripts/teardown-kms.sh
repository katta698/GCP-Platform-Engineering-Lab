#!/usr/bin/env bash
# The teardown experiment: find out whether a Cloud KMS key ring can be deleted.
#
#   ./scripts/teardown-kms.sh --stage report
#   ./scripts/teardown-kms.sh --stage destroy-versions
#   ./scripts/teardown-kms.sh --stage delete
#
# Why this is an experiment and not a cleanup script
# --------------------------------------------------
# Two authoritative sources currently disagree.
#
# Google's resource-hierarchy documentation says: "You can delete key rings,
# keys, and key versions in some circumstances", and "When you delete a key
# ring, its name becomes available for reuse, but names of deleted keys can't be
# reused."
#
# The Terraform provider's own documentation for google_kms_crypto_key says:
# "CryptoKeys cannot be deleted from Google Cloud Platform. Destroying a
# Terraform-managed CryptoKey will remove it from state and delete all
# CryptoKeyVersions, rendering the key unusable, but will not delete the
# resource from the project."
#
# Both cannot be right. Key and key-version deletion reached GA during 2026 and
# the provider note reads like it predates that. This script runs the documented
# deletion chain against a real key ring and records which source matches
# reality, because that is the only way to know.
#
# The chain Google documents:
#   1. every key version must be DESTROYED (not merely scheduled)
#   2. the key must have NO automatic rotation scheduled
#   3. the key must not have been created by Autokey
#   4. then the key can be deleted
#   5. once every key is deleted, the key ring can be deleted
#
# Step 1 is why this is staged rather than one command. A destroyed version
# spends `destroyScheduledDuration` in DESTROY_SCHEDULED first, which this week
# sets to 24h instead of taking the 30-day default - and a version in
# DESTROY_SCHEDULED is still a BILLED version.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-security}"
KEYRING="${KEYRING:-wk12-secrets}"
KEY="${KEY:-wk12-app-db-password}"
LOCATION="${LOCATION:-global}"
STAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }

kms() { gcloud kms "$@" --location="$LOCATION" --project="$PROJECT"; }

report() {
  say "does the key ring still exist?"
  if kms keyrings describe "$KEYRING" >/dev/null 2>&1; then
    echo "YES - key ring ${KEYRING} is present"
  else
    echo "NO - key ring ${KEYRING} is gone"
    return 0
  fi

  say "keys in the ring"
  kms keys list --keyring="$KEYRING" \
    --format='table(name.basename(), purpose, rotationPeriod, destroyScheduledDuration)'

  say "key versions and their states"
  # The states that matter: ENABLED and DISABLED are billed, DESTROY_SCHEDULED
  # is ALSO billed, DESTROYED is not.
  for K in $(kms keys list --keyring="$KEYRING" --format='value(name.basename())'); do
    echo "key: ${K}"
    kms keys versions list --key="$K" --keyring="$KEYRING" \
      --format='table(name.basename(), state, createTime, destroyTime)'
  done

  say "billing consequence"
  echo "Google counts a key version as ACTIVE - and therefore billed - if it is"
  echo "Enabled, Disabled, or Scheduled for destruction. Only DESTROYED stops the"
  echo "charge. Count the non-DESTROYED versions above to know what is still metering."
}

destroy_versions() {
  say "removing the automatic rotation schedule"
  # A documented precondition for deleting a key: "The key doesn't have
  # automatic key rotation scheduled." Terraform cannot express the absence,
  # so this is a deliberate out-of-band step and it is recorded here.
  kms keys update "$KEY" --keyring="$KEYRING" --remove-rotation-schedule
  kms keys describe "$KEY" --keyring="$KEYRING" --format='value(rotationPeriod)' \
    | grep -q . && echo "WARNING: rotation schedule still present" || echo "rotation schedule removed"

  say "scheduling every version for destruction"
  for V in $(kms keys versions list --key="$KEY" --keyring="$KEYRING" \
               --filter='state!=DESTROYED AND state!=DESTROY_SCHEDULED' \
               --format='value(name.basename())'); do
    echo "destroying version ${V}"
    kms keys versions destroy "$V" --key="$KEY" --keyring="$KEYRING" --quiet
  done

  say "state after scheduling"
  kms keys versions list --key="$KEY" --keyring="$KEYRING" \
    --format='table(name.basename(), state, destroyTime)'

  echo
  echo "Versions are now DESTROY_SCHEDULED, not DESTROYED. They remain billed."
  echo "destroyScheduledDuration on this key is 24h, so re-run --stage delete after"
  echo "the destroyTime above has passed. Attempting it sooner is itself a result:"
  echo "it shows the precondition being enforced."
}

attempt_delete() {
  say "attempting to delete the key (expect a precondition failure if versions are not DESTROYED)"
  set +e
  OUT="$(kms keys delete "$KEY" --keyring="$KEYRING" --quiet 2>&1)"
  RC=$?
  set -e
  printf '%s\n' "$OUT"
  echo "exit code: ${RC}"

  if [[ $RC -ne 0 ]]; then
    say "key deletion refused - recording the precondition, not retrying"
    report
    return 0
  fi

  say "key deleted. Attempting to delete the key ring"
  set +e
  OUT="$(kms keyrings delete "$KEYRING" --quiet 2>&1)"
  RC=$?
  set -e
  printf '%s\n' "$OUT"
  echo "exit code: ${RC}"

  if [[ $RC -eq 0 ]]; then
    echo
    echo "RESULT: key ring DELETED. Google's documentation is current and the"
    echo "Terraform provider's note that CryptoKeys cannot be deleted is out of date."
  else
    echo
    echo "RESULT: key deleted, key ring NOT deleted. Record the exact error above;"
    echo "do not paraphrase it."
  fi
}

case "$STAGE" in
  report)           report ;;
  destroy-versions) destroy_versions ;;
  delete)           attempt_delete ;;
  *) echo "usage: $0 --stage {report|destroy-versions|delete}" >&2; exit 2 ;;
esac

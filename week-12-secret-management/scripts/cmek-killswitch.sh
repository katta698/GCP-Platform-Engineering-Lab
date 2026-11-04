#!/usr/bin/env bash
# Prove that CMEK makes the key holder a kill switch for the secret.
#
#   ./scripts/cmek-killswitch.sh
#
# What this demonstrates, and why it is the week's security evidence
# ------------------------------------------------------------------
# "The secret is encrypted with a customer-managed key" is the kind of sentence
# that passes a compliance review and teaches nobody anything. The question it
# dodges is: what can the key holder actually do?
#
# This answers it. Disabling the key VERSION - not deleting it, not changing a
# single IAM binding, not touching the secret at all - makes the secret
# unreadable. The payload is still there. The caller still holds
# secretAccessor. Secret Manager simply cannot decrypt it, because Secret
# Manager decrypts as its own service agent using a key that is now disabled.
#
# This is the denial that carries the post, so it is attempted as an identity
# that genuinely HOLDS secretmanager.versions.access. An under-privileged
# attempt fails with a permission error that looks identical and proves nothing
# - the rule the lab learned in Week 02 and re-earned in Week 11.
#
# Reversible: disable is not destroy. The version goes back to ENABLED at the
# end, in a trap, so a failure midway does not leave the secret dark.
#
# Note on cost, which is counter-intuitive and worth stating in the post: a
# DISABLED key version is still a billed key version. Google counts a version
# as active if it is "Enabled, Disabled, or Scheduled for destruction".
# Disabling a key stops it working and does not stop it charging.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-security}"
SECRET="${SECRET:-wk12-app-db-password}"
KEYRING="${KEYRING:-wk12-secrets}"
KEY="${KEY:-wk12-app-db-password}"
LOCATION="${LOCATION:-global}"

say() { printf '\n== %s\n' "$*"; }

# The version to toggle. Taken as the primary rather than assumed to be 1,
# because the KMS rotation schedule on this key will eventually make it not 1.
VERSION="$(gcloud kms keys describe "$KEY" \
  --keyring="$KEYRING" --location="$LOCATION" --project="$PROJECT" \
  --format='value(primary.name)' | sed 's#.*/##')"

say "identity performing the read"
gcloud config get-value account

say "confirming the caller can actually read the secret (control, before any denial)"
if gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "OK: secret is readable with the key enabled"
else
  echo "ABORT: the caller cannot read the secret even with the key enabled." >&2
  echo "A denial measured from here would prove nothing about CMEK." >&2
  exit 1
fi

restore() {
  say "re-enabling key version ${VERSION}"
  gcloud kms keys versions enable "$VERSION" \
    --key="$KEY" --keyring="$KEYRING" --location="$LOCATION" --project="$PROJECT" || true
  # Decrypt does not come back instantly; give it a moment before asserting.
  sleep 20
  if gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT" >/dev/null 2>&1; then
    echo "OK: secret readable again"
  else
    echo "WARNING: secret still unreadable after re-enable. Wait and re-check;" >&2
    echo "do not conclude the data is lost - disable is not destroy." >&2
  fi
}
trap restore EXIT

say "disabling key version ${VERSION} - the secret itself is not touched"
gcloud kms keys versions disable "$VERSION" \
  --key="$KEY" --keyring="$KEYRING" --location="$LOCATION" --project="$PROJECT"

# KMS key state changes are not instant at the consuming service.
say "waiting 30s for the disable to take effect at Secret Manager"
sleep 30

say "attempting the read again, same identity, same permissions"
set +e
OUT="$(gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT" 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUT"
echo "exit code: ${RC}"

say "secret metadata is still intact - only the ability to decrypt is gone"
gcloud secrets describe "$SECRET" --project="$PROJECT" \
  --format='value(name,createTime,replication.auto.customerManagedEncryption.kmsKeyName)'

if [[ $RC -eq 0 ]]; then
  echo
  echo "RESULT: the read SUCCEEDED with the key disabled. The week's CMEK claim is" >&2
  echo "wrong as written and the post must be corrected rather than the test retried." >&2
  exit 1
fi

echo
echo "RESULT: read denied with the key disabled, and granted with it enabled."
echo "The key holder, not the secret's IAM policy, decided whether the value could be read."

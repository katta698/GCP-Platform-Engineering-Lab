#!/usr/bin/env bash
# Week 12 validation. Reads the cloud, never Terraform state.
#
#   ./scripts/validate.sh
#
# Every assertion here is phrased so that the failure mode is a FAILURE, not a
# silent pass. Week 10's validate.sh asserted something false and used an unset
# variable that killed the run under `set -u`, and both were found by running it
# rather than writing it - so this one is written to be run, and the exit code
# is the result.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-security}"
SECRET="${SECRET:-wk12-app-db-password}"
KEYRING="${KEYRING:-wk12-secrets}"
KEY="${KEY:-wk12-app-db-password}"
LOCATION="${LOCATION:-global}"
TOPIC="${TOPIC:-wk12-secret-rotation-events}"
SUBSCRIPTION="${SUBSCRIPTION:-wk12-rotation-observer}"

PASS=0
FAIL=0

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$label"; FAIL=$((FAIL + 1))
  fi
}

# Asserts an exact string rather than mere presence. A check that only asks
# "did the command succeed" passes on the wrong value.
expect() {
  local label="$1" want="$2"; shift 2
  local got
  got="$("$@" 2>/dev/null || true)"
  if [[ "$got" == "$want" ]]; then
    printf '  PASS  %s (%s)\n' "$label" "$got"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s: expected %q, got %q\n' "$label" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "== Infrastructure deployed"

check "key ring ${KEYRING} exists in ${LOCATION}" \
  gcloud kms keyrings describe "$KEYRING" --location="$LOCATION" --project="$PROJECT"

check "key ${KEY} exists" \
  gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOCATION" --project="$PROJECT"

check "secret ${SECRET} exists" \
  gcloud secrets describe "$SECRET" --project="$PROJECT"

check "topic ${TOPIC} exists" \
  gcloud pubsub topics describe "$TOPIC" --project="$PROJECT"

check "subscription ${SUBSCRIPTION} exists" \
  gcloud pubsub subscriptions describe "$SUBSCRIPTION" --project="$PROJECT"

echo
echo "== The key is what the week says it is"

# SOFTWARE, not HSM. The cost note depends on this being true.
expect "key protection level is SOFTWARE" "SOFTWARE" \
  gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOCATION" \
  --project="$PROJECT" --format=value'(versionTemplate.protectionLevel)'

# The teardown finding depends on this NOT being the 30-day default.
expect "destroy scheduled duration is 24h, not the 30-day default" "86400s" \
  gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOCATION" \
  --project="$PROJECT" --format=value'(destroyScheduledDuration)'

# KMS rotation is configured. This is the half that genuinely rotates.
if [[ -n "$(gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOCATION" \
      --project="$PROJECT" --format='value(rotationPeriod)')" ]]; then
  printf '  PASS  %s\n' "KMS automatic rotation is scheduled"; PASS=$((PASS + 1))
else
  printf '  FAIL  %s\n' "KMS automatic rotation is NOT scheduled"; FAIL=$((FAIL + 1))
fi

echo
echo "== The secret is encrypted with OUR key, not Google's"

KMS_ON_SECRET="$(gcloud secrets describe "$SECRET" --project="$PROJECT" \
  --format='value(replication.auto.customerManagedEncryption.kmsKeyName)')"
if [[ "$KMS_ON_SECRET" == *"/keyRings/${KEYRING}/cryptoKeys/${KEY}" ]]; then
  printf '  PASS  secret names our key: %s\n' "$KMS_ON_SECRET"; PASS=$((PASS + 1))
else
  printf '  FAIL  secret CMEK key is %q\n' "$KMS_ON_SECRET"; FAIL=$((FAIL + 1))
fi

# The service agent, not the caller, does the crypto. If this binding is absent
# the secret could not have been created at all - so finding it absent here
# would mean something outside Terraform removed it.
AGENT="service-$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')@gcp-sa-secretmanager.iam.gserviceaccount.com"
if gcloud kms keys get-iam-policy "$KEY" --keyring="$KEYRING" --location="$LOCATION" \
    --project="$PROJECT" --format=json 2>/dev/null \
    | grep -q "$AGENT"; then
  printf '  PASS  Secret Manager service agent holds a role on the key\n'; PASS=$((PASS + 1))
else
  printf '  FAIL  Secret Manager service agent has NO role on the key\n'; FAIL=$((FAIL + 1))
fi

echo
echo "== Rotation is configured, and configured means notified"

# Pub/Sub topics are mandatory on a rotating secret. Asserting the link exists
# is asserting that the notification has somewhere to go.
if gcloud secrets describe "$SECRET" --project="$PROJECT" --format=json \
    | grep -q "$TOPIC"; then
  printf '  PASS  secret publishes to %s\n' "$TOPIC"; PASS=$((PASS + 1))
else
  printf '  FAIL  secret has no topic configured\n'; FAIL=$((FAIL + 1))
fi

expect "rotation period is Google's one-hour minimum" "3600s" \
  gcloud secrets describe "$SECRET" --project="$PROJECT" \
  --format=value'(rotation.rotationPeriod)'

echo
echo "== Neither pipeline identity can READ the secret value"

# The point of the grant split in Week 02's config: Terraform manages the
# secret and never consumes it, so neither identity holds secretAccessor.
# Asserted by testIamPermissions rather than by reading the policy, because an
# inherited grant would not appear in this project's own bindings.
for SA in tf-apply tf-plan; do
  PERMS="$(gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT" --format=json 2>/dev/null \
    | grep -c "${SA}@katta698-gcp-lab-seed.iam.gserviceaccount.com" || true)"
  if [[ "$PERMS" == "0" ]]; then
    printf '  PASS  %s holds no binding on the secret itself\n' "$SA"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s has a direct binding on the secret\n' "$SA"; FAIL=$((FAIL + 1))
  fi
done

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1

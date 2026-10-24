#!/usr/bin/env bash
# How long does a group membership change take to reach IAM?
#
#   ORG_ID=... ./scripts/measure-membership-lag.sh [trials]
#
# Google documents a propagation delay for membership arriving from an EXTERNAL
# IdP and says it can take up to several hours. There is no external IdP here -
# membership is written straight through the Cloud Identity API - so that figure
# does not describe this configuration and must not be quoted for it. This
# measures the configuration we actually built.
#
# Method, copied from week-03's measure-enforcement-lag.py because the lesson
# there applies unchanged: ONE SUCCESS FOLLOWED BY ONE FAILURE IS NOT A
# MEASUREMENT. It cannot tell a propagation delay from a transient error. Three
# trials each direction, ten-second poll, and the range gets published rather
# than the best observation.
#
# SAFETY: this script removes a group membership and puts it back. If it dies
# mid-cycle the subject is left without access, which is harmless here (the
# subject is a demo service account that holds nothing else) but would not be
# harmless on a real access group. The restore runs in a trap, not at the end of
# the happy path - week-03 learned that by leaving an org policy degraded when a
# lag script crashed.
set -uo pipefail

: "${ORG_ID:?set ORG_ID}"
SEED="${SEED_PROJECT:-katta698-gcp-lab-seed}"
DOMAIN="${DOMAIN:-jayanthkatta.com}"
GROUP="${GROUP:-grp-gcp-log-readers@${DOMAIN}}"
SUBJECT="${SUBJECT:-group-access-demo@${SEED}.iam.gserviceaccount.com}"
LOGGING_PROJECT="${LOGGING_PROJECT:-katta698-gcp-logging}"
TRIALS="${1:-3}"
POLL=10
CEILING=600   # stop waiting after 10 minutes and report that, rather than hang

CI=(--billing-project="$SEED")

restore() {
  # Idempotent: adding an existing membership is a no-op error we swallow.
  gcloud identity groups memberships add --group-email="$GROUP" \
    --member-email="$SUBJECT" --roles=MEMBER "${CI[@]}" >/dev/null 2>&1
  echo "  [restore] membership put back"
}
trap restore EXIT

can_read() {
  gcloud logging read 'timestamp>="1970-01-01T00:00:00Z"' \
    --project="$LOGGING_PROJECT" --limit=1 \
    --impersonate-service-account="$SUBJECT" >/dev/null 2>&1
}

# Wait until can_read returns $1 (0 = can read, 1 = cannot). Echo the seconds.
wait_until() {
  local want="$1" waited=0
  while (( waited < CEILING )); do
    if can_read; then (( want == 0 )) && { echo "$waited"; return 0; }
    else (( want == 1 )) && { echo "$waited"; return 0; }
    fi
    sleep "$POLL"; waited=$(( waited + POLL ))
  done
  echo "TIMEOUT"
  return 1
}

echo "Measuring membership propagation, ${TRIALS} trial(s) each direction."
echo "Subject: ${SUBJECT%%@*}@...  Group: ${GROUP%%@*}@..."
echo "Poll ${POLL}s, ceiling ${CEILING}s. A ceiling hit is reported, not retried."
echo

revoke_times=() grant_times=()

for (( i = 1; i <= TRIALS; i++ )); do
  echo "--- trial $i ---"

  # Make sure we start from a known state rather than assuming one.
  restore >/dev/null
  if ! can_read; then
    echo "  waiting for the starting state (access present)..."
    wait_until 0 >/dev/null || { echo "  cannot establish starting state; aborting"; exit 1; }
  fi

  echo -n "  revoke: removing membership... "
  gcloud identity groups memberships delete --group-email="$GROUP" \
    --member-email="$SUBJECT" "${CI[@]}" >/dev/null 2>&1
  t=$(wait_until 1); echo "access gone after ${t}s"
  revoke_times+=("$t")

  echo -n "  grant:  adding membership back... "
  gcloud identity groups memberships add --group-email="$GROUP" \
    --member-email="$SUBJECT" --roles=MEMBER "${CI[@]}" >/dev/null 2>&1
  t=$(wait_until 0); echo "access back after ${t}s"
  grant_times+=("$t")
  echo
done

summarise() { # name, values...
  local name="$1"; shift
  printf "  %-8s %s\n" "$name" "$(IFS=, ; echo "$*")s"
}

echo "== Result =="
summarise "revoke" "${revoke_times[@]}"
summarise "grant"  "${grant_times[@]}"
echo
echo "Publish the RANGE. A single figure from one trial cannot distinguish a"
echo "propagation delay from a transient error, and the reverse direction is the"
echo "operationally dangerous one: an operator who removes someone from a group"
echo "during an incident and sees access persist will conclude the removal"
echo "failed and start removing other things."

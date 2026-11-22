#!/usr/bin/env bash
# Watch the cost guardrails refuse something. Re-runnable, and it cleans up.
#
#   bash scripts/prove_guardrails.sh
#
# A guardrail nobody has seen refuse anything is a claim. This attempts a
# forbidden machine type and expects the denial, then attempts an allowed one
# and expects success - because a guardrail that blocks everything is just as
# broken, and only the second test can tell the difference.
#
# ORG POLICY IS NOT INSTANT. On 2026-11-22 the constraint was created at
# 17:13:30Z, still allowed an n2-standard-8 a minute later, and refused at
# 17:17:45Z. Anything created in that window is deleted here, but a run
# straight after an apply will report a false negative.
set -uo pipefail

PROJECT="${PROJECT:-katta698-gcp-net-hub}"
ZONE="${ZONE:-us-central1-a}"
SUBNET="${SUBNET:-dev-us-central1}"
BIG="${BIG:-n2-standard-8}"
SMALL="${SMALL:-e2-micro}"
META="enable-oslogin=TRUE,block-project-ssh-keys=TRUE"
PASS=0; FAIL=0

g() { gcloud "$@" 2>&1 | tr -d '\r'; }
nuke() { gcloud compute instances delete "$1" --project="$PROJECT" --zone="$ZONE" \
          --quiet >/dev/null 2>&1 && echo "       (created despite the policy - deleted)"; }

echo "== the forbidden case: ${BIG}"
OUT="$(g compute instances create gr-proof-big --project="$PROJECT" --zone="$ZONE" \
       --machine-type="$BIG" --subnet="$SUBNET" --no-address --metadata="$META")"
if echo "$OUT" | grep -qi "denied by org policy"; then
  echo "  PASS  refused"
  echo "$OUT" | grep -i "customConstraints\|denied by org policy" | head -2 | sed 's/^/        /'
  PASS=$((PASS+1))
else
  echo "  FAIL  NOT refused - the guardrail is not in force"
  echo "$OUT" | head -3 | sed 's/^/        /'
  nuke gr-proof-big
  FAIL=$((FAIL+1))
fi

echo
echo "== the allowed case: ${SMALL} (a guardrail that blocks everything is also broken)"
OUT="$(g compute instances create gr-proof-small --project="$PROJECT" --zone="$ZONE" \
       --machine-type="$SMALL" --subnet="$SUBNET" --no-address --metadata="$META")"
if echo "$OUT" | grep -qi "Created"; then
  echo "  PASS  allowed"
  gcloud compute instances delete gr-proof-small --project="$PROJECT" --zone="$ZONE" \
    --quiet >/dev/null 2>&1 && echo "        deleted"
  PASS=$((PASS+1))
else
  echo "  FAIL  an allowed size was refused - the constraint is too broad"
  echo "$OUT" | head -3 | sed 's/^/        /'
  FAIL=$((FAIL+1))
fi

echo
echo "== leftovers"
LEFT="$(g compute instances list --project="$PROJECT" --filter='name~^gr-proof' --format='value(name)' | grep -c . || true)"
[ "$LEFT" = "0" ] && { echo "  PASS  nothing left running"; PASS=$((PASS+1)); } \
                  || { echo "  FAIL  ${LEFT} test instance(s) still exist"; FAIL=$((FAIL+1)); }

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
echo "Not covered here: Cloud SQL tiers (API not enabled; proven on Week 36) and"
echo "the denied-services policy, which did NOT refuse Bigtable - see"
echo "docs/COST-GUARDRAILS.md."
[ "$FAIL" -eq 0 ] || exit 1

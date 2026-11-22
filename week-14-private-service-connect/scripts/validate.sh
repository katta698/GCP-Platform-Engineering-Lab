#!/usr/bin/env bash
# Week 14 validation. Reads the cloud, never Terraform state.
#
#   ./scripts/validate.sh
#
# Written BEFORE the deploy, so it runs against live infrastructure while the
# week is up. Week 13's was written after teardown and has still never been
# executed; a validate.sh that has never run is a claim, not a check.
#
# The assertions that matter here are the two the week rests on:
#   - the endpoint address is OURS and sits outside every subnet range
#   - the probe VM has no external IP, so neither path is a plain internet call
# Everything else is existence, which the Terraform run already proved.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-net-hub}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-${REGION}-a}"
NETWORK="${NETWORK:-psc-lab}"
SUBNET="${SUBNET:-psc-lab-${REGION}}"
VM="${VM:-psc-probe}"
RULE="${RULE:-psc-apis}"
ENDPOINT="${ENDPOINT:-10.99.0.2}"

PASS=0
FAIL=0

# gcloud on Windows emits CRLF, which makes a string compare fail against
# output that looks identical.
g() { gcloud "$@" 2>/dev/null | tr -d '\r'; }

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$label"; FAIL=$((FAIL + 1))
  fi
}

expect() {
  local label="$1" want="$2"; shift 2
  local got; got="$("$@" 2>/dev/null | tr -d '\r' || true)"
  if [[ "$got" == "$want" ]]; then
    printf '  PASS  %s (%s)\n' "$label" "${got:-empty}"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s: expected %q, got %q\n' "$label" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

note() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "== Infrastructure deployed"

check "network ${NETWORK} exists" \
  gcloud compute networks describe "$NETWORK" --project="$PROJECT"

check "subnet ${SUBNET} exists" \
  gcloud compute networks subnets describe "$SUBNET" \
    --project="$PROJECT" --region="$REGION"

check "forwarding rule ${RULE} exists" \
  gcloud compute forwarding-rules describe "$RULE" --global --project="$PROJECT"

echo
echo "== Private Google Access is on, because it is half the comparison"

expect "subnet has privateIpGoogleAccess" "True" \
  gcloud compute networks subnets describe "$SUBNET" --project="$PROJECT" \
    --region="$REGION" --format='value(privateIpGoogleAccess)'

echo
echo "== The endpoint address is ours, and is not a Google VIP"

expect "address purpose is PRIVATE_SERVICE_CONNECT" "PRIVATE_SERVICE_CONNECT" \
  gcloud compute addresses describe psc-apis-endpoint-ip --global \
    --project="$PROJECT" --format='value(purpose)'

expect "forwarding rule targets all-apis" "all-apis" \
  bash -c "gcloud compute forwarding-rules describe '$RULE' --global \
    --project='$PROJECT' --format='value(target)' | tr -d '\r' | sed 's#.*/##'"

ADDR="$(g compute addresses describe psc-apis-endpoint-ip --global \
        --project="$PROJECT" --format='value(address)')"
if [[ "$ADDR" == "$ENDPOINT" ]]; then
  note "endpoint address is ${ADDR}"
else
  bad "endpoint address is ${ADDR:-unset}, expected ${ENDPOINT}"
fi

# The documented rule: the endpoint "can't be within the range of subnets
# configured in the VPC network". Asserting it here means the figure that
# shows it is checked, not just captured.
CIDR="$(g compute networks subnets list --project="$PROJECT" \
        --filter="network~${NETWORK}$" --format='value(ipCidrRange)')"
INSIDE=0
for r in $CIDR; do
  python - "$ADDR" "$r" <<'PY' && INSIDE=1
import ipaddress, sys
print("") if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2]) else sys.exit(1)
PY
done
if [[ "$INSIDE" -eq 0 ]]; then
  note "endpoint sits outside every subnet range (${CIDR//$'\n'/, })"
else
  bad "endpoint ${ADDR} is INSIDE a subnet range - Google should have rejected this"
fi

echo
echo "== The client has nothing of its own"

expect "probe has no external IP" "" \
  gcloud compute instances describe "$VM" --project="$PROJECT" --zone="$ZONE" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)'

expect "probe is in ${SUBNET}" "$SUBNET" \
  bash -c "gcloud compute instances describe '$VM' --project='$PROJECT' \
    --zone='$ZONE' --format='value(networkInterfaces[0].subnetwork)' \
    | tr -d '\r' | sed 's#.*/##'"

# No Cloud NAT anywhere on this network: without this, a working call proves
# nothing, because NAT would carry it regardless of which mechanism is used.
NATS="$(g compute routers list --project="$PROJECT" \
        --filter="network~${NETWORK}$" --format='value(name)' | grep -c . || true)"
if [[ "$NATS" == "0" ]]; then
  note "no Cloud Router or NAT on ${NETWORK}"
else
  bad "${NATS} router(s) on ${NETWORK} - a NAT would make both paths work regardless"
fi

echo
echo "== The route the comparison turns on"

RT="$(g compute routes list --project="$PROJECT" \
      --filter="network~${NETWORK}$ AND destRange=0.0.0.0/0 AND nextHopGateway~default-internet-gateway" \
      --format='value(name)' | head -1)"
if [[ -n "$RT" ]]; then
  note "default internet-gateway route present: ${RT}"
else
  bad "no default internet-gateway route - Private Google Access cannot work, and break-pga.sh has nothing to delete"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
echo
echo "Both paths should now work from the probe. To prove they are different:"
echo "  ./scripts/break-pga.sh --json docs/pga-vs-psc.json"

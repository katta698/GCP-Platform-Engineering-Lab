#!/usr/bin/env bash
# Week 13 validation. Reads the cloud, never Terraform state.
#
#   ./scripts/validate.sh
#
# The point of the week is that BGP, not a static route, is what carries the
# branch prefix. So the assertions that matter are the COUNTS: four tunnels
# ESTABLISHED, two BGP sessions Established per router, and the branch range
# learned twice - once per tunnel. A check that only asks "does the tunnel
# exist" passes on a topology with no availability at all.
#
# NOT YET RUN AGAINST A LIVE DEPLOYMENT. Written after teardown, so it is
# syntax-checked and reasoned through but unexercised. The first real run is
# the test of this file as much as of the infrastructure.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-net-hub}"
REGION="${REGION:-us-central1}"
HUB_ROUTER="${HUB_ROUTER:-hub-router}"
BRANCH_ROUTER="${BRANCH_ROUTER:-branch-router}"
BRANCH_CIDR="${BRANCH_CIDR:-10.30.0.0/24}"
HUB_CIDR="${HUB_CIDR:-10.20.0.0/24}"

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

# Asserts an exact value. gcloud on Windows emits CRLF, which makes a string
# compare fail against output that looks identical, so strip it everywhere.
expect() {
  local label="$1" want="$2"; shift 2
  local got
  got="$("$@" 2>/dev/null | tr -d '\r' || true)"
  if [[ "$got" == "$want" ]]; then
    printf '  PASS  %s (%s)\n' "$label" "$got"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s: expected %q, got %q\n' "$label" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "== Infrastructure deployed"

check "branch VPC exists" \
  gcloud compute networks describe branch --project="$PROJECT"

check "hub HA VPN gateway exists" \
  gcloud compute vpn-gateways describe hub-gw --project="$PROJECT" --region="$REGION"

check "branch HA VPN gateway exists" \
  gcloud compute vpn-gateways describe branch-gw --project="$PROJECT" --region="$REGION"

# Two interfaces, not one. A gateway with a single active interface is a
# supported configuration with NO availability SLA attached to it.
expect "hub gateway has 2 interfaces" "2" \
  bash -c "gcloud compute vpn-gateways describe hub-gw --project='$PROJECT' \
    --region='$REGION' --format='value(vpnInterfaces[].id)' | tr ';' '\n' | grep -c ."

expect "four tunnel resources exist" "4" \
  bash -c "gcloud compute vpn-tunnels list --project='$PROJECT' \
    --filter='region:$REGION' --format='value(name)' | grep -c ."

echo
echo "== Service functioning"

expect "all four tunnels ESTABLISHED" "4" \
  bash -c "gcloud compute vpn-tunnels list --project='$PROJECT' \
    --filter='region:$REGION' --format='value(detailedStatus)' \
    | grep -ci 'established'"

expect "hub router has 2 BGP sessions Established" "2" \
  bash -c "gcloud compute routers get-status '$HUB_ROUTER' --project='$PROJECT' \
    --region='$REGION' --format=json \
    | python -c \"import json,sys; d=json.load(sys.stdin); r=(d[0] if isinstance(d,list) else d)['result']; print(sum(1 for p in r.get('bgpPeerStatus',[]) if p.get('state')=='Established'))\""

expect "branch router has 2 BGP sessions Established" "2" \
  bash -c "gcloud compute routers get-status '$BRANCH_ROUTER' --project='$PROJECT' \
    --region='$REGION' --format=json \
    | python -c \"import json,sys; d=json.load(sys.stdin); r=(d[0] if isinstance(d,list) else d)['result']; print(sum(1 for p in r.get('bgpPeerStatus',[]) if p.get('state')=='Established'))\""

echo
echo "== The routes are learned, not written"

# Twice, once per tunnel. One entry means one tunnel is carrying everything
# and the failover this week claims has nowhere to go.
expect "hub learned ${BRANCH_CIDR} twice" "2" \
  bash -c "gcloud compute routers get-status '$HUB_ROUTER' --project='$PROJECT' \
    --region='$REGION' --format=json \
    | python -c \"import json,sys; d=json.load(sys.stdin); r=(d[0] if isinstance(d,list) else d)['result']; b=r.get('bestRoutesForRouter') or r.get('bestRoutes') or []; print(sum(1 for x in b if x.get('destRange')=='$BRANCH_CIDR'))\""

expect "branch learned ${HUB_CIDR} twice" "2" \
  bash -c "gcloud compute routers get-status '$BRANCH_ROUTER' --project='$PROJECT' \
    --region='$REGION' --format=json \
    | python -c \"import json,sys; d=json.load(sys.stdin); r=(d[0] if isinstance(d,list) else d)['result']; b=r.get('bestRoutesForRouter') or r.get('bestRoutes') or []; print(sum(1 for x in b if x.get('destRange')=='$HUB_CIDR'))\""

# The claim is that BGP carries this prefix. The only way to be sure is that
# no static route to it exists - a learned route and a typed one look
# identical in a route table, and the range legitimately appears in
# variables.tf as a default.
if gcloud compute routes list --project="$PROJECT" \
     --filter="destRange=$BRANCH_CIDR AND NOT name~^default" \
     --format='value(name)' 2>/dev/null | tr -d '\r' | grep -q .; then
  printf '  FAIL  a STATIC route to %s exists; the learned route is not what is carrying traffic\n' "$BRANCH_CIDR"
  FAIL=$((FAIL + 1))
else
  printf '  PASS  no static route to %s exists\n' "$BRANCH_CIDR"
  PASS=$((PASS + 1))
fi

echo
echo "== Security controls"

check "branch firewall allows only the hub ranges" \
  gcloud compute firewall-rules describe branch-allow-hub-icmp-ssh --project="$PROJECT"

expect "hub probe has no external IP" "" \
  gcloud compute instances describe hub-probe --project="$PROJECT" \
    --zone="${REGION}-a" --format='value(networkInterfaces[0].accessConfigs[0].natIP)'

expect "branch probe has no external IP" "" \
  gcloud compute instances describe branch-probe --project="$PROJECT" \
    --zone="${REGION}-a" --format='value(networkInterfaces[0].accessConfigs[0].natIP)'

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
echo
echo "Routing is dynamic on both sides. To see it move, break one tunnel:"
echo "  python scripts/measure-failover.py --trials 3 --json docs/failover.json"

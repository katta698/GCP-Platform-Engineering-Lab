#!/usr/bin/env bash
# Delete the default internet-gateway route and see which path survives.
#
#   ./scripts/break-pga.sh                 # measure, then restore
#   ./scripts/break-pga.sh --json out.json
#
# Private Google Access reaches Google's own external addresses through the
# VPC's default internet gateway - the documentation requires "appropriate
# routes whose next hops are the default internet gateway". A Private Service
# Connect endpoint is an internal address in this VPC and never uses that
# route. Deleting the route is therefore the whole experiment: one call should
# stop working and the other should not.
#
# Both calls are real HTTPS to the same API from the same VM. The only
# difference is which address curl connects to:
#   PGA  - default DNS, so a Google public VIP
#   PSC  - --resolve pins the connection to the endpoint, with correct SNI
#
# The route is recreated in a trap on every path out, including Ctrl-C. A
# script that degrades a control restores it however it exits.
#
# ONE CONSEQUENCE FOR TEARDOWN. Google creates that default route itself when
# the network is created, so Terraform never owned it. Once this script has
# recreated it by hand, `terraform destroy` fails on the network with:
#
#   The network resource '...psc-lab' is already being used by
#   '...routes/default-route-<hash>'
#
# Delete the route before destroying:
#
#   gcloud compute routes delete <name> --project="$PROJECT" --quiet
#
# Nothing bills in the meantime - a network and a route are free - but the
# destroy does not complete until it is gone.
set -euo pipefail

PROJECT="${PROJECT:-katta698-gcp-net-hub}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-${REGION}-a}"
VM="${VM:-psc-probe}"
NETWORK="${NETWORK:-psc-lab}"
ENDPOINT="${ENDPOINT:-10.99.0.2}"
API_HOST="${API_HOST:-storage.googleapis.com}"
API_PATH="${API_PATH:-/storage/v1/b?project=${PROJECT}}"
JSON=""
[[ "${1:-}" == "--json" ]] && JSON="${2:?--json needs a path}"

say() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# gcloud on Windows emits CRLF, which makes every string compare fail against
# output that looks identical.
g() { gcloud "$@" 2>/dev/null | tr -d '\r'; }

# Filter on the network only: `routes list` rejects the combined filter with
# "Invalid list filter expression", which would leave ROUTE empty and make this
# script report "no default route" on a network that has one.
ROUTE="$(g compute routes list --project="$PROJECT" --filter="network~${NETWORK}" \
  --format='value(name,destRange,nextHopGateway)' \
  | awk '$2 == "0.0.0.0/0" && $3 ~ /default-internet-gateway/ {print $1; exit}')"

if [[ -z "$ROUTE" ]]; then
  echo "No default internet-gateway route on ${NETWORK}." >&2
  echo "Either it was already deleted, or the network name is wrong." >&2
  exit 1
fi
say "default route on ${NETWORK}: ${ROUTE}"

restore() {
  if ! g compute routes list --project="$PROJECT" --format='value(name)' \
       | grep -qx "$ROUTE"; then
    say "restoring ${ROUTE}"
    gcloud compute routes create "$ROUTE" \
      --project="$PROJECT" --network="$NETWORK" \
      --destination-range=0.0.0.0/0 \
      --next-hop-gateway=default-internet-gateway \
      --priority=1000 >/dev/null 2>&1 \
      && say "restored" || say "WARNING: could not restore ${ROUTE}"
  fi
}
trap restore EXIT INT TERM

# One HTTPS call, run on the VM over IAP. Prints the status code, or 000 when
# the connection never completed - which is the failure this measures.
probe() {
  local mode="$1" curlargs=""
  [[ "$mode" == "psc" ]] && curlargs="--resolve ${API_HOST}:443:${ENDPOINT}"
  g compute ssh "$VM" --project="$PROJECT" --zone="$ZONE" --tunnel-through-iap \
    --command "curl -s -o /dev/null --max-time 8 -w '%{http_code}' ${curlargs} https://${API_HOST}${API_PATH} || echo 000" \
    | tail -1
}

both() {
  local label="$1" pga psc
  pga="$(probe pga)"; pga="${pga: -3}"
  psc="$(probe psc)"; psc="${psc: -3}"
  # To STDERR on purpose. The caller captures stdout to read the two codes, so
  # a `say` here would be swallowed and the per-stage numbers would exist
  # nowhere in the log - which is what happened on the first run: the only
  # surviving record of the measurement was the summary line.
  say "${label}: Private Google Access -> ${pga:-000}   PSC endpoint -> ${psc:-000}" >&2
  echo "${pga:-000} ${psc:-000}"
}

say "baseline, with the default route in place"
read -r BASE_PGA BASE_PSC <<<"$(both baseline | tail -1)"

if [[ "$BASE_PGA" == "000" || "$BASE_PSC" == "000" ]]; then
  echo "ABORT: both paths must work before breaking one means anything." >&2
  exit 1
fi

say "deleting ${ROUTE}"
gcloud compute routes delete "$ROUTE" --project="$PROJECT" --quiet >/dev/null
say "deleted - Private Google Access now has no path to Google's addresses"

read -r BROKE_PGA BROKE_PSC <<<"$(both 'route deleted' | tail -1)"

restore
sleep 5
read -r BACK_PGA BACK_PSC <<<"$(both 'route restored' | tail -1)"

echo
if [[ "$BROKE_PGA" == "000" && "$BROKE_PSC" != "000" ]]; then
  echo "RESULT: deleting the default internet-gateway route broke Private Google"
  echo "  Access (${BASE_PGA} -> ${BROKE_PGA}) and left the PSC endpoint working"
  echo "  (${BASE_PSC} -> ${BROKE_PSC}). The VM, the subnet flag and the firewall"
  echo "  were untouched. Only the route changed."
  RC=0
else
  echo "RESULT: NOT the expected outcome. PGA ${BASE_PGA}->${BROKE_PGA},"
  echo "  PSC ${BASE_PSC}->${BROKE_PSC}. This is a failed measurement, not a"
  echo "  finding - do not write it up as one."
  RC=1
fi

if [[ -n "$JSON" ]]; then
  cat > "$JSON" <<EOF
{
  "route": "${ROUTE}",
  "endpoint": "${ENDPOINT}",
  "api": "https://${API_HOST}${API_PATH}",
  "baseline":       { "pga": "${BASE_PGA}",  "psc": "${BASE_PSC}" },
  "route_deleted":  { "pga": "${BROKE_PGA}", "psc": "${BROKE_PSC}" },
  "route_restored": { "pga": "${BACK_PGA}",  "psc": "${BACK_PSC}" }
}
EOF
  say "written to ${JSON}"
fi
exit "$RC"

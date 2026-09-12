#!/usr/bin/env bash
# Verify Week 04 against GCP, independently of Terraform state.
#
#   ORG_ID=... HOST_PROJECT=... SERVICE_PROJECT=... ./scripts/validate.sh
#
# Two things this checks that a "does it exist" script would not: that the VM has
# no external address (a cost assertion, not a connectivity one), and that the
# organization policy exception at workloads/dev is actually differing from the
# organization — which is the claim Week 03 made and could not demonstrate.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
: "${HOST_PROJECT:?set HOST_PROJECT}"
: "${SERVICE_PROJECT:?set SERVICE_PROJECT}"

# Required rather than defaulted. A folder ID is not a secret, but this repo is
# public and the convention is that numeric identifiers live in the gitignored
# tfvars and arrive through the environment — a default here would have been the
# one place they got committed.
#
#   DEV_FOLDER_ID=$(gcloud resource-manager folders list --folder=<workloads> #     --filter="displayName=dev" --format="value(name)")
: "${DEV_FOLDER_ID:?set DEV_FOLDER_ID}"
: "${PROD_FOLDER_ID:?set PROD_FOLDER_ID}"
DEV_FOLDER="$DEV_FOLDER_ID"
PROD_FOLDER="$PROD_FOLDER_ID"
ZONE="${ZONE:-us-central1-a}"
INSTANCE="${INSTANCE:-dev-app-01}"

echo "== The network is CUSTOM mode =="
echo "   Auto mode would create a subnet in every region Google has, now and in"
echo "   every region added later, with ranges nobody chose."
mode=$(gcloud compute networks describe hub --project="$HOST_PROJECT" \
  --format="value(autoCreateSubnetworks)" 2>/dev/null || true)
if [[ "${mode,,}" == "false" ]]; then
  echo "  OK - auto_create_subnetworks=false"
else
  echo "  FAIL - expected false, got '${mode:-nothing}'"
  exit 1
fi
gcloud compute networks subnets list --project="$HOST_PROJECT" \
  --filter="network:hub" --format="table(name,region,ipCidrRange,privateIpGoogleAccess)"
echo

echo "== Shared VPC: host enabled, and the spoke attached =="
attached=$(gcloud compute shared-vpc list-associated-resources "$HOST_PROJECT" \
  --format="value(id)" 2>/dev/null || true)
if grep -q "$SERVICE_PROJECT" <<<"$attached"; then
  echo "  OK - $SERVICE_PROJECT is attached to $HOST_PROJECT"
else
  echo "  FAIL - service project is not attached. Got: ${attached:-nothing}"
  exit 1
fi
echo

echo "== The instance draws its address from another project's subnet =="
echo "   That is the whole of Shared VPC in one value: the VM lives in the"
echo "   service project, the subnet lives in the host project."
ip=$(gcloud compute instances describe "$INSTANCE" --project="$SERVICE_PROJECT" \
  --zone="$ZONE" --format="value(networkInterfaces[0].networkIP)" 2>/dev/null || true)
ext=$(gcloud compute instances describe "$INSTANCE" --project="$SERVICE_PROJECT" \
  --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
echo "  internal: ${ip:-none}"

# The external-IP check is a COST assertion. An external IPv4 address is billed
# per hour whether traffic flows or not and is not in the free tier, so an
# accidental one is a bill that appears without anything breaking.
if [[ -z "$ext" ]]; then
  echo "  OK - no external IP. Nothing here is billable per hour."
else
  echo "  FAIL - external IP $ext is attached, and is being billed."
  exit 1
fi
echo

echo "== Free-tier shape =="
echo "   Four values decide whether this week costs nothing or costs money."
gcloud compute instances describe "$INSTANCE" --project="$SERVICE_PROJECT" \
  --zone="$ZONE" --format="value(machineType.basename(),zone.basename())" \
  | sed 's/^/  machine+zone: /'
gcloud compute disks describe "$INSTANCE" --project="$SERVICE_PROJECT" --zone="$ZONE" \
  --format="value(type.basename(),sizeGb)" 2>/dev/null | sed 's/^/  disk: /'
echo "   Expect e2-micro, us-central1-a, pd-standard, 10GB."
echo

echo "== The hierarchical firewall policy is ATTACHED, not merely created =="
echo "   A policy attached to nothing is inert. Creating and attaching are"
echo "   separately authorised — different IAM roles entirely."
assoc=$(gcloud compute firewall-policies list --folder="${DEV_FOLDER%/*}" \
  --format="value(name)" 2>/dev/null || true)
gcloud compute firewall-policies describe workloads-baseline \
  --organization="$ORG_ID" --format="value(associations[].attachmentTarget)" 2>/dev/null \
  | sed 's/^/  attached to: /' || echo "  (describe needs compute.firewallPolicies.get)"
echo

echo "== The Week 03 exception, finally demonstrable =="
echo "   Three constraints, three scopes. One row should differ in one column."
printf "  %-44s %-6s %-6s %-6s\n" "constraint" "org" "dev" "prod"
for c in compute.managed.requireOsLogin \
         compute.managed.blockProjectSshKeys \
         compute.managed.disableSerialPortAccess; do
  o=$(gcloud org-policies describe "$c" --organization="$ORG_ID" --effective \
      --format='value(spec.rules[0].enforce)' 2>/dev/null || true)
  d=$(gcloud org-policies describe "$c" --folder="$DEV_FOLDER" --effective \
      --format='value(spec.rules[0].enforce)' 2>/dev/null || true)
  p=$(gcloud org-policies describe "$c" --folder="$PROD_FOLDER" --effective \
      --format='value(spec.rules[0].enforce)' 2>/dev/null || true)
  printf "  %-44s %-6s %-6s %-6s\n" "$c" "$o" "$d" "$p"
done

serial_org=$(gcloud org-policies describe compute.managed.disableSerialPortAccess \
  --organization="$ORG_ID" --effective --format='value(spec.rules[0].enforce)' 2>/dev/null || true)
serial_dev=$(gcloud org-policies describe compute.managed.disableSerialPortAccess \
  --folder="$DEV_FOLDER" --effective --format='value(spec.rules[0].enforce)' 2>/dev/null || true)

if [[ "${serial_org,,}" == "true" && "${serial_dev,,}" == "false" ]]; then
  echo "  OK - the organization refuses serial console access; workloads/dev does not."
  echo "       Inheritance and override, evaluated by Google rather than asserted."
else
  echo "  FAIL - expected org=True dev=False, got org=${serial_org} dev=${serial_dev}"
  exit 1
fi
echo

echo "== The instance complies with what is now enforced =="
# Checked as VALUES rather than by attempting a violation. A validate script
# should not weaken a live instance to prove a control works, and it does not
# need to: the constraints refuse non-compliant requests, so the compliant state
# is itself the evidence that they were satisfied at creation.
meta=$(gcloud compute instances describe "$INSTANCE" --project="$SERVICE_PROJECT" \
  --zone="$ZONE" --format="json(metadata.items)" 2>/dev/null || echo '{}')
oslogin=$(python -c "
import json,sys
d=json.loads(sys.argv[1] or '{}')
print(next((i['value'] for i in d.get('metadata',{}).get('items',[]) if i['key']=='enable-oslogin'),''))
" "$meta")

if [[ "${oslogin^^}" == "TRUE" ]]; then
  echo "  OK - enable-oslogin=TRUE, satisfying compute.managed.requireOsLogin."
else
  echo "  FAIL - enable-oslogin is '${oslogin:-unset}' while the constraint is enforced."
  exit 1
fi

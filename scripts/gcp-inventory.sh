#!/usr/bin/env bash
# Report the current Google Cloud footprint for this account.
#
# This is the script that answers "what do I actually have?". Run it after
# docs/SETUP.md step 2, and any time the answer is unclear. It is read-only —
# every command is a list or describe, nothing is created or changed.
#
# Usage:  ./scripts/gcp-inventory.sh
set -uo pipefail

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is not installed or not on PATH. See docs/SETUP.md step 1." >&2
  exit 1
fi

hr() { printf '\n== %s ==\n' "$1"; }

hr "Authenticated accounts"
gcloud auth list

hr "Active configuration"
gcloud config list

hr "Organizations"
gcloud organizations list 2>/dev/null || echo "(none — no Cloud Identity organization)"

hr "Folders"
ORG=$(gcloud organizations list --format='value(ID)' 2>/dev/null | head -1)
if [[ -n "${ORG}" ]]; then
  gcloud resource-manager folders list --organization="${ORG}"
else
  echo "(skipped — no organization)"
fi

hr "Projects"
gcloud projects list

hr "Billing accounts"
gcloud billing accounts list 2>/dev/null || echo "(none, or Billing API not reachable)"

hr "Per-project detail"
for P in $(gcloud projects list --format='value(projectId)' 2>/dev/null); do
  printf '\n--- %s ---\n' "$P"

  echo "Billing:"
  gcloud billing projects describe "$P" --format='value(billingAccountName,billingEnabled)' 2>/dev/null \
    || echo "  (cannot read billing for this project)"

  echo "Enabled services:"
  gcloud services list --project="$P" --format='value(config.name)' 2>/dev/null | sed 's/^/  /' \
    || echo "  (cannot list services)"

  echo "Compute instances:"
  gcloud compute instances list --project="$P" --format='table(name,zone,machineType,status)' 2>/dev/null \
    || echo "  (Compute API not enabled)"

  echo "Storage buckets:"
  gcloud storage buckets list --project="$P" --format='value(name)' 2>/dev/null | sed 's/^/  /' \
    || echo "  (Storage API not enabled)"
done

hr "Done"
echo "Redact organization IDs, billing account IDs and project numbers before"
echo "pasting any of this into a committed file."

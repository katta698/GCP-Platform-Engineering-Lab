#!/usr/bin/env bash
# Verify what was actually deployed, independently of Terraform state.
set -euo pipefail
echo "== Organization =="
gcloud organizations list
echo
echo "== Folders =="
gcloud resource-manager folders list --organization="${ORG_ID:?set ORG_ID}"
echo
echo "== Projects =="
gcloud projects list

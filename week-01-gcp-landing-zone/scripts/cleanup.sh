#!/usr/bin/env bash
# This week is meant to stay deployed. Every later week sits inside the
# hierarchy it creates, so tearing it down orphans the whole lab.
set -euo pipefail
if [[ "${1:-}" != "--i-really-mean-it" ]]; then
  echo "Refusing: week 01 is permanent infrastructure." >&2
  echo "Re-run with --i-really-mean-it if you are dismantling the lab." >&2
  exit 1
fi
cd "$(dirname "$0")/../terraform/environments/${ENV:-dev}"
terraform destroy

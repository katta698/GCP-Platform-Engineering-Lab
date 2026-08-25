#!/usr/bin/env bash
# Week 02 is permanent infrastructure and is exempt from teardown.
#
# Destroying it does not save money — pools, providers, service accounts and IAM
# bindings are free. It only removes the identity every later week authenticates
# with, which breaks every remote workspace at once and leaves no credential on
# any machine that can rebuild it. Recovery means signing in as a human, running
# this week by hand again, and re-entering the workspace variables.
#
# The guard exists so that a blanket "destroy last week" reflex cannot do that
# by accident.
set -euo pipefail

if [[ "${1:-}" != "--i-really-mean-it" ]]; then
  cat <<'MSG'
Refusing to destroy Week 02.

This week costs nothing to leave running and is the authentication path for
every later week. If you genuinely intend to tear down the lab's CI identity:

    ./scripts/cleanup.sh --i-really-mean-it

Before you do: confirm you can still authenticate as a human with the
organization roles needed to rebuild it, or the lab becomes unmanageable.
MSG
  exit 1
fi

cd "$(dirname "$0")/../terraform"
terraform destroy

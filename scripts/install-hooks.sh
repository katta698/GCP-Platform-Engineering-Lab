#!/usr/bin/env bash
# Install this repo's git hooks. Run once per clone.
#
#   ./scripts/install-hooks.sh
#
# .git/hooks is not tracked, so a hook committed to the repo does nothing until
# somebody points git at it. This sets core.hooksPath to a tracked directory,
# which means the hooks travel with the repo and a fresh clone gets them with
# one command instead of a copy-paste ritual nobody remembers.
#
# CI in .github/workflows/repo-checks.yml runs the same checks and is the real
# guarantee - it cannot be bypassed with --no-verify. The hook exists only to
# fail in two seconds on a workstation rather than two minutes later on a
# runner.
set -euo pipefail

cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "core.hooksPath -> .githooks"
echo
echo "Installed:"
for h in .githooks/*; do
  [[ -f "$h" ]] && echo "  $(basename "$h")"
done
echo
echo "To bypass once (and you should have a reason):  git push --no-verify"
echo "CI runs the same checks regardless, so a bypass only defers the failure."

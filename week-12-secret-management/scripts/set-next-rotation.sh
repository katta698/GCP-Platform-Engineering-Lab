#!/usr/bin/env bash
# Set next_rotation_time in terraform.tfvars to N minutes from now.
#
#   ./scripts/set-next-rotation.sh 8
#
# Why this exists rather than a timestamp() expression in the config: a computed
# timestamp changes on every plan, so the secret would show a permanent diff and
# "no changes" would stop meaning anything.
#
# Why it exists rather than being typed by hand: Secret Manager refuses a
# next_rotation_time less than five minutes in the future, and a rejected apply
# after the grants are in place costs a full round trip. The floor is checked
# here instead.
#
# The rotation PERIOD stays at one hour - Google's minimum. This moves only the
# next notification, which is what makes a second observation possible without
# waiting an hour for the schedule to come round.
set -euo pipefail

MINUTES="${1:-8}"
TFVARS="$(dirname "$0")/../terraform/terraform.tfvars"

if (( MINUTES < 6 )); then
  echo "refusing: Secret Manager rejects next_rotation_time under 5 minutes out," >&2
  echo "and an apply takes time of its own. Use 6 or more." >&2
  exit 1
fi

[[ -f "$TFVARS" ]] || { echo "no terraform.tfvars at $TFVARS" >&2; exit 1; }

# -u for UTC and -d for relative arithmetic: both are GNU date. This runs under
# Git Bash on Windows, which ships GNU coreutils, so this is safe here and is
# NOT portable to macOS.
WHEN="$(date -u -d "+${MINUTES} minutes" +%Y-%m-%dT%H:%M:%SZ)"

# A literal replacement, not a regex on the value, so a malformed existing value
# cannot survive by failing to match.
python - "$TFVARS" "$WHEN" <<'PY'
import re, sys
path, when = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
new, n = re.subn(
    r'^(next_rotation_time\s*=\s*).*$',
    lambda m: m.group(1) + '"' + when + '"',
    text,
    flags=re.M,
)
if n != 1:
    sys.exit(f"expected exactly one next_rotation_time line, found {n}")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(new)
PY

echo "next_rotation_time = ${WHEN} (UTC), ${MINUTES} minutes from now"

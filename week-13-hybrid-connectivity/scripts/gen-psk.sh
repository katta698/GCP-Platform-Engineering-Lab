#!/usr/bin/env bash
# Write a random IKE pre-shared key into the gitignored tfvars.
#
#   ./scripts/gen-psk.sh
set -euo pipefail
TFVARS="$(dirname "$0")/../terraform/terraform.tfvars"
PSK="$(openssl rand -base64 32 | tr -d '\n=' | cut -c1-32)"
python - "$TFVARS" "$PSK" <<'PY'
import io, re, sys
path, psk = sys.argv[1], sys.argv[2]
text = io.open(path, encoding="utf-8").read() if __import__("os").path.exists(path) else ""
line = 'shared_secret = "%s"' % psk
if re.search(r'^shared_secret\s*=', text, re.M):
    text = re.sub(r'^shared_secret\s*=.*$', line, text, flags=re.M)
else:
    text = (text.rstrip("\n") + "\n" + line + "\n").lstrip("\n")
io.open(path, "w", encoding="utf-8").write(text)
PY
echo "shared_secret written to terraform.tfvars (32 chars, not printed)"

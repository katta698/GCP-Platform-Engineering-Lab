#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""How long after disabling a CMEK key does the secret actually stop being readable?

    python scripts/measure-cmek-revocation.py --timeout 900

Why this exists
---------------
`cmek-killswitch.sh` disabled the key version, waited 30 seconds, and the read
still SUCCEEDED. The script correctly refused to report that as a working
control.

Two explanations, and they have opposite consequences:

  a) propagation - the disable takes longer than 30s to reach Secret Manager,
     and the read fails eventually. The control works; 30s was a bad guess.
  b) no revocation - Secret Manager does not decrypt per access. It would be
     holding plaintext, or a cached data key, so disabling the KMS key stops
     NEW encryption and never stops reads of what already exists.

If (b), then "the key holder is a kill switch" is wrong, and the honest version
is much more interesting: CMEK gives you custody of the key, not a revocation
button for data already encrypted with it.

This script decides between them by polling instead of assuming, and reports
the time it took. It NEVER prints the secret value - only whether the read
worked.

Restores the key in a finally block. Week 03's lag script crashed mid-cycle
having already degraded a control and left the organization in a state the
published post contradicted. A script that degrades a control restores it on
every path out.
"""
import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
GCLOUD = shutil.which("gcloud")
if not GCLOUD:
    sys.exit("gcloud not on PATH")


def run(args):
    """Return (rc, stdout, stderr) - never merged. Week 11's lesson."""
    p = subprocess.run([GCLOUD, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, p.stdout, p.stderr


def stamp():
    return datetime.now(timezone.utc).strftime("%H:%M:%S")


def can_read(secret, project):
    """True if the value is retrievable. The value itself is never returned."""
    rc, _out, err = run(["secrets", "versions", "access", "latest",
                         "--secret=" + secret, "--project=" + project])
    return rc == 0, err.strip()


def key_state(key, keyring, location, project, version):
    rc, out, _ = run(["kms", "keys", "versions", "describe", version,
                      "--key=" + key, "--keyring=" + keyring,
                      "--location=" + location, "--project=" + project,
                      "--format=value(state)"])
    return out.strip() if rc == 0 else "UNKNOWN"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="katta698-gcp-security")
    ap.add_argument("--secret", default="wk12-app-db-password")
    ap.add_argument("--key", default="wk12-app-db-password")
    ap.add_argument("--keyring", default="wk12-secrets")
    ap.add_argument("--location", default="global")
    ap.add_argument("--version", default="1")
    ap.add_argument("--timeout", type=int, default=900,
                    help="seconds to keep polling before concluding reads never stop")
    ap.add_argument("--poll", type=int, default=20)
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    kw = dict(key=args.key, keyring=args.keyring, location=args.location,
              project=args.project, version=args.version)

    ok, _ = can_read(args.secret, args.project)
    if not ok:
        sys.exit("ABORT: the secret is not readable BEFORE the key is disabled.\n"
                 "A denial measured from here would prove nothing about CMEK.")
    print(f"[{stamp()}] control: secret IS readable with the key enabled")

    record = {"secret": args.secret, "poll_seconds": args.poll,
              "timeout_seconds": args.timeout, "samples": []}
    disabled_at = None

    try:
        rc, _, err = run(["kms", "keys", "versions", "disable", args.version,
                          "--key=" + args.key, "--keyring=" + args.keyring,
                          "--location=" + args.location, "--project=" + args.project])
        if rc != 0:
            sys.exit(f"could not disable the key version:\n{err}")
        disabled_at = time.time()
        state = key_state(**kw)
        print(f"[{stamp()}] key version {args.version} disabled (state={state}); "
              f"polling the read every {args.poll}s for up to {args.timeout}s")
        record["key_state_after_disable"] = state

        denied_after = None
        while time.time() - disabled_at < args.timeout:
            elapsed = round(time.time() - disabled_at)
            ok, err = can_read(args.secret, args.project)
            record["samples"].append({"elapsed_s": elapsed, "readable": ok})
            if ok:
                print(f"[{stamp()}] +{elapsed:>4}s  read STILL SUCCEEDS")
            else:
                print(f"[{stamp()}] +{elapsed:>4}s  read DENIED")
                print("    " + (err.splitlines() or [""])[0][:200])
                denied_after = elapsed
                record["denied_after_seconds"] = elapsed
                record["denial_error"] = err[:600]
                break
            time.sleep(args.poll)

        print()
        if denied_after is not None:
            print(f"RESULT: reads stopped working {denied_after}s after the key was disabled.")
            print("  CMEK revocation WORKS; it is just not immediate. Publish the number,")
            print("  and note that any check made sooner would report a working control as broken.")
            record["conclusion"] = "revocation_works_with_lag"
        else:
            print(f"RESULT: reads NEVER stopped working within {args.timeout}s.")
            print("  Disabling the KMS key did not revoke access to data already encrypted")
            print("  with it. CMEK is custody of the key, NOT a revocation switch for")
            print("  existing secret versions. This is the finding - do not retry it into")
            print("  the answer that was expected.")
            record["conclusion"] = "no_revocation_observed"
    finally:
        if disabled_at is not None:
            rc, _, err = run(["kms", "keys", "versions", "enable", args.version,
                              "--key=" + args.key, "--keyring=" + args.keyring,
                              "--location=" + args.location, "--project=" + args.project])
            print(f"\n[{stamp()}] key version re-enabled "
                  f"(state={key_state(**kw)}){'' if rc == 0 else ' - FAILED: ' + err[:200]}")
            time.sleep(15)
            ok, _ = can_read(args.secret, args.project)
            print(f"[{stamp()}] secret readable again: {ok}")
            record["restored"] = ok

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2)
        print(f"written to {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

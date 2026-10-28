#!/usr/bin/env python3
"""How long after a PAM grant expires does the role binding actually disappear?

The week's whole claim is that access ends without anybody ending it. That is
only true from the moment the binding leaves the folder's IAM policy, and the
gap between "the grant says expired" and "the policy says gone" is a window in
which access is still live and nobody is watching.

Nothing publishes that number. So measure it.

Method, copied deliberately from Week 03's enforcement-lag measurement:

  - poll the folder's IAM policy every POLL seconds across the expiry boundary
  - record the first poll at which the binding is absent
  - repeat THREE times and publish the RANGE

One success followed by one failure cannot distinguish a propagation delay from
a transient error. Week 03 wrote up a lag from n=1 and had to redo it; the
reverse lag it then discovered - the dangerous direction - only showed up
because the measurement was repeated.

Each trial costs at least 30 minutes of wall clock, because 1800s is the
shortest grant PAM will issue. Three trials is therefore a ~2 hour run. That is
the cost of the number being real.

Restores nothing and changes nothing: it only reads. Week 03's first version of
this kind of script crashed having already degraded a control and left it that
way, so this one deliberately has no write path at all.

Usage:
  PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... python scripts/measure-expiry-lag.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

# subprocess cannot launch a bare `gcloud` on Windows: it is a .CMD shim and
# CreateProcess does not apply PATHEXT. Week 03 lost a measurement run to this.
GCLOUD = shutil.which("gcloud")
if not GCLOUD:
    sys.exit("gcloud not found on PATH")

FOLDER = os.environ.get("PLATFORM_FOLDER_ID")
SEED = os.environ.get("SEED_PROJECT_ID")
if not FOLDER or not SEED:
    sys.exit("set PLATFORM_FOLDER_ID and SEED_PROJECT_ID")

SUBJECT = f"jit-access-demo@{SEED}.iam.gserviceaccount.com"
ROLE = os.environ.get("ELEVATED_ROLE", "roles/iam.securityReviewer")
POLL = int(os.environ.get("POLL", "10"))
# How long to keep polling past the expected expiry before calling it.
PATIENCE = int(os.environ.get("PATIENCE", "900"))


def run(args: list[str]) -> tuple[int, str]:
    p = subprocess.run([GCLOUD, *args], capture_output=True, text=True)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def binding_present() -> bool:
    """Is the subject bound to the elevated role on the folder, right now?"""
    rc, out = run([
        "resource-manager", "folders", "get-iam-policy", FOLDER,
        "--format=json",
    ])
    if rc != 0:
        raise RuntimeError(f"could not read the folder policy: {out[:200]}")
    policy = json.loads(out)
    for b in policy.get("bindings", []):
        if b.get("role") == ROLE and f"serviceAccount:{SUBJECT}" in b.get("members", []):
            return True
    return False


def active_grant_expiry() -> datetime | None:
    """Expiry of the one ACTIVE grant, if there is one."""
    rc, out = run([
        "pam", "grants", "list",
        "--entitlement=folder-security-review",
        f"--folder={FOLDER}", "--location=global", "--format=json",
    ])
    if rc != 0:
        return None
    for g in json.loads(out or "[]"):
        if g.get("state") != "ACTIVE":
            continue
        tl = g.get("timeline", {})
        for ev in tl.get("events", []):
            if "expire" in json.dumps(ev).lower():
                for v in ev.values():
                    if isinstance(v, dict) and "expireTime" in v:
                        return datetime.fromisoformat(
                            v["expireTime"].replace("Z", "+00:00"))
    return None


def one_trial(n: int) -> float | None:
    print(f"\n=== trial {n} ===")
    if not binding_present():
        print("  no binding present - request and approve a grant first")
        return None

    expiry = active_grant_expiry()
    if expiry:
        print(f"  grant expires at {expiry.isoformat()}")
    else:
        print("  could not read an expiry; measuring from the binding instead")

    print(f"  polling every {POLL}s for the binding to disappear...")
    started = time.time()
    while True:
        if not binding_present():
            gone_at = datetime.now(timezone.utc)
            if expiry:
                lag = (gone_at - expiry).total_seconds()
                print(f"  binding gone at {gone_at.isoformat()}  ->  lag {lag:.0f}s")
                return lag
            waited = time.time() - started
            print(f"  binding gone after {waited:.0f}s of polling (no expiry reference)")
            return waited
        if time.time() - started > PATIENCE + 1800:
            print(f"  gave up after {(time.time()-started):.0f}s - binding still present")
            return None
        time.sleep(POLL)


def main() -> int:
    trials = int(os.environ.get("TRIALS", "3"))
    print(f"Measuring PAM grant-expiry lag: {trials} trial(s), {POLL}s poll.")
    print(f"  folder:  folders/{FOLDER}")
    print(f"  subject: {SUBJECT}")
    print(f"  role:    {ROLE}")
    print("\nEach trial needs its own approved grant. The script waits for the")
    print("current one to expire, then stops - request and approve the next.")

    results: list[float] = []
    for i in range(1, trials + 1):
        r = one_trial(i)
        if r is None:
            print("  trial produced no measurement")
            continue
        results.append(r)
        if i < trials:
            input("\n  Request and approve the next grant, then press Enter... ")

    print("\n=== result ===")
    if not results:
        print("No measurements. Nothing to publish - say that rather than guessing.")
        return 1
    print(f"  trials: {len(results)}")
    print(f"  lags:   {', '.join(f'{r:.0f}s' for r in results)}")
    print(f"  range:  {min(results):.0f}s to {max(results):.0f}s")
    if len(results) < 3:
        print("\n  Fewer than three trials. This is an observation, not a")
        print("  measurement - publish it as one or run it again.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

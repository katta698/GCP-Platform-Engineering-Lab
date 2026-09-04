#!/usr/bin/env python3
"""Measure the delay between writing an org policy and it actually enforcing.

    SEED_PROJECT=... python scripts/measure-enforcement-lag.py [trials]

Why this exists. The Week 03 write-up originally stated, as a property of the
platform, that enforcement lags the policy write by roughly two minutes. That
came from a single observation: one bucket creation succeeded shortly after the
flip, and one failed a little later. One success followed by one failure is not
a measurement. It is consistent with a lag, and equally consistent with a
transient error, an unrelated eventual-consistency effect, or coincidence.

So this repeats the cycle: return the constraint to dry run, confirm an
unlabelled bucket is allowed again, flip it to enforced, then poll until a
bucket is actually refused, timing from the moment the apply returned.

Terraform stays the source of truth throughout. The switch is the HCP workspace
variable, never a gcloud write, so this cannot leave state drifted against the
organization.

Two hazards this script is built around, both hit for real on 2026-09-03:

  1. It deliberately puts the organization into a state the published post
     contradicts -- the constraint back in dry run, denying nothing. The first
     version crashed at exactly that point and left it there, live, until it was
     noticed. The cycle now sits in try/finally, so the last thing this process
     does is restore enforcement.

  2. gcloud and terraform are .CMD shims on Windows, and CreateProcess does not
     apply PATHEXT. subprocess.run(["gcloud", ...]) raises FileNotFoundError
     even though the same command works in a shell. Both are resolved by path.

Buckets are deleted whichever way each attempt goes.
"""
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

WS = "ws-YgLRYUAUoMXeAogk"
CONSTRAINT = "custom.requireTerraformLabelsOnBuckets"
CREDS = r"C:/Users/katta/AppData/Roaming/terraform.d/credentials.tfrc.json"
TF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "terraform")

GCLOUD = shutil.which("gcloud")
TERRAFORM = shutil.which("terraform")
if not GCLOUD or not TERRAFORM:
    sys.exit("gcloud and terraform must both be on PATH")

SEED = os.environ["SEED_PROJECT"]
TRIALS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
POLL_S = 10
MAX_WAIT_S = 600


def set_enforce(enabled):
    """Point the workspace's `enforce` map at the constraint, or empty it."""
    tok = json.load(open(CREDS))["credentials"]["app.terraform.io"]["token"]
    hdr = {"Authorization": "Bearer " + tok,
           "Content-Type": "application/vnd.api+json"}
    listing = json.load(urllib.request.urlopen(urllib.request.Request(
        "https://app.terraform.io/api/v2/workspaces/%s/vars" % WS, headers=hdr)))
    vid = next(v["id"] for v in listing["data"]
               if v["attributes"]["key"] == "enforce")
    value = '{ "%s" = true }' % CONSTRAINT if enabled else "{}"
    body = {"data": {"type": "vars", "id": vid,
                     "attributes": {"value": value, "hcl": True}}}
    urllib.request.urlopen(urllib.request.Request(
        "https://app.terraform.io/api/v2/workspaces/%s/vars/%s" % (WS, vid),
        data=json.dumps(body).encode(), headers=hdr, method="PATCH"))


def apply():
    subprocess.run([TERRAFORM, "apply", "-auto-approve", "-input=false",
                    "-no-color"], cwd=TF_DIR, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def try_bucket():
    """Create an unlabelled bucket. True if allowed. Always cleans up."""
    name = "wk03-lag-%d" % int(time.time() * 1000)
    r = subprocess.run([GCLOUD, "storage", "buckets", "create", "gs://" + name,
                        "--project=" + SEED, "--location=us-central1",
                        "--uniform-bucket-level-access"],
                       capture_output=True, text=True)
    allowed = r.returncode == 0
    if allowed:
        subprocess.run([GCLOUD, "storage", "rm", "--recursive", "gs://" + name,
                        "--quiet"], capture_output=True, text=True)
    elif "412" not in r.stderr and "violates" not in r.stderr:
        # Refused for a reason other than the constraint. Counting that as
        # enforcement would repeat the error this script exists to correct.
        print("      unexpected failure: " + r.stderr.strip()[:160])
    return allowed


def wait_until(want_allowed):
    """Poll until the constraint reaches the wanted state. Returns seconds."""
    t0 = time.time()
    while time.time() - t0 < MAX_WAIT_S:
        if try_bucket() == want_allowed:
            return time.time() - t0
        time.sleep(POLL_S)
    return None


results = []
try:
    for n in range(1, TRIALS + 1):
        print("")
        print("=== trial %d of %d ===" % (n, TRIALS))

        print("  returning the constraint to dry run")
        set_enforce(False)
        apply()
        back = wait_until(True)
        if back is None:
            print("  ABORT: still denying after 10 minutes in dry run")
            break
        print("  dry run in effect again after %.0fs" % back)

        print("  promoting to enforced")
        set_enforce(True)
        apply()
        lag = wait_until(False)
        if lag is None:
            print("  ABORT: never denied within 10 minutes")
            break
        results.append(lag)
        print("  ENFORCED after %.0fs" % lag)
finally:
    print("")
    print("  restoring enforced state")
    try:
        set_enforce(True)
        apply()
        print("  restored")
    except Exception as exc:
        print("  RESTORE FAILED: %s" % exc)
        print("  Set enforce in the gcp-week-03 workspace by hand and apply.")

print("")
print("=== result ===")
if results:
    print("  observations: " + ", ".join("%.0fs" % r for r in results))
    print("  min %.0fs  max %.0fs  n=%d  poll resolution %ds"
          % (min(results), max(results), len(results), POLL_S))
    print("  A lag is only known to within one poll interval. Report a range.")
else:
    print("  no usable observations")

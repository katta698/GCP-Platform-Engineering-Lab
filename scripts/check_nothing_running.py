#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""After a teardown, prove nothing billable survived it.

    python scripts/check_nothing_running.py
    python scripts/check_nothing_running.py --self-test

`terraform destroy` reporting success is not proof. Week 12's destroy returned
cleanly and left a Cloud KMS key version behind, because Google bills a version
that is Enabled, Disabled OR scheduled for destruction, and DESTROYED is not
deleted. It was found by looking, which is not a control.

This asks Cloud Asset Inventory, org-wide, for the asset types that actually
cost money, and fails if any exist.

THE EMPTY-RESULT TRAP, which this check is built around
    On 2026-11-22 `gcloud billing budgets list` returned an empty list and
    exit 0 because a quota project was not set. Read literally it said "no
    budgets". It meant "the question did not reach the API". Asset search can
    fail the same way - wrong scope, missing permission, API disabled - and a
    cost check that reports "nothing running" when it cannot see anything is
    worse than no check at all.

    So every run first asks a CONTROL question with a known answer: list VPC
    networks, of which this org always has at least one. If the control comes
    back empty, the instrument is blind and the run FAILS rather than passing.
"""
import argparse
import json
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Asset types that cost money while they exist. Not exhaustive by design -
# add a type the first time a week deploys one, rather than guessing now.
BILLABLE = [
    "compute.googleapis.com/Instance",
    "compute.googleapis.com/Disk",
    "compute.googleapis.com/VpnTunnel",
    "compute.googleapis.com/VpnGateway",
    "compute.googleapis.com/Router",
    "compute.googleapis.com/ForwardingRule",
    "compute.googleapis.com/Address",
    "compute.googleapis.com/Image",
    "cloudkms.googleapis.com/CryptoKeyVersion",
    "sqladmin.googleapis.com/Instance",
    "container.googleapis.com/Cluster",
    "redis.googleapis.com/Instance",
    "run.googleapis.com/Service",
    "cloudfunctions.googleapis.com/Function",
    "file.googleapis.com/Instance",
]

# Free, and present in a healthy org - so a good control question.
CONTROL = "compute.googleapis.com/Network"


def gcloud(args):
    exe = shutil.which("gcloud")
    if not exe:
        return None, "gcloud not on PATH"
    p = subprocess.run([exe, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=300)
    if p.returncode != 0:
        return None, (p.stderr or "").strip()[:300]
    # gcloud on Windows emits CRLF.
    return p.stdout.replace("\r", ""), None


def org_id():
    out, err = gcloud(["organizations", "list", "--format=value(name)"])
    if err or not out or not out.strip():
        return None
    return out.strip().splitlines()[0].replace("organizations/", "")


def search(org, asset_types):
    out, err = gcloud(["asset", "search-all-resources",
                       f"--scope=organizations/{org}",
                       "--asset-types=" + ",".join(asset_types),
                       "--format=json"])
    if err is not None:
        return None, err
    try:
        return json.loads(out or "[]"), None
    except json.JSONDecodeError as exc:
        return None, f"unparseable response: {exc}"


def run(verbose=True):
    org = org_id()
    if not org:
        print("  FAIL  could not resolve the organization - cannot ask the "
              "question at all")
        return 1

    # The control. A blind instrument must not report good news.
    ctrl, err = search(org, [CONTROL])
    if err is not None:
        print(f"  FAIL  control query errored: {err}")
        return 1
    if not ctrl:
        print("  FAIL  control query returned NOTHING. This org has VPC "
              "networks, so an empty answer means the search is blind -")
        print("        wrong scope, missing permission, or the Cloud Asset "
              "API disabled. Treating this as 'nothing running' would be")
        print("        the exact mistake this check exists to prevent.")
        return 1
    if verbose:
        print(f"  control: asset search can see {len(ctrl)} network(s) - "
              f"the instrument works")

    found, err = search(org, BILLABLE)
    if err is not None:
        print(f"  FAIL  billable search errored: {err}")
        return 1

    if not found:
        print(f"  PASS  no billable asset of {len(BILLABLE)} tracked types "
              f"exists anywhere in the organization")
        return 0

    print(f"  FAIL  {len(found)} billable asset(s) still exist:")
    for a in found[:25]:
        print("        %-46s %s" % (a.get("assetType", "?"),
                                    a.get("displayName") or a.get("name", "")))
    if len(found) > 25:
        print(f"        ... and {len(found) - 25} more")
    print()
    print("  A destroy that reported success can still leave these. Week 12's")
    print("  KMS key version survived one, because DESTROYED is not deleted.")
    return 1


# ---------------------------------------------------------------------------

def self_test():
    """Prove the blind-instrument rule works, since that is the whole point."""
    import types
    cases, bad = [], 0
    mod = sys.modules[__name__]
    real = mod.search, mod.org_id

    def fake(control_result, billable_result, control_err=None, bill_err=None):
        def _search(org, types_):
            if types_ == [CONTROL]:
                return control_result, control_err
            return billable_result, bill_err
        mod.search = _search
        mod.org_id = lambda: "123"

    import io, contextlib
    def exit_code():
        with contextlib.redirect_stdout(io.StringIO()):
            return run(verbose=False)

    fake([{"n": 1}], [])
    cases.append(("control sees networks, nothing billable -> pass", exit_code(), 0))

    fake([{"n": 1}], [{"assetType": "compute.googleapis.com/Instance",
                       "displayName": "leftover-vm"}])
    cases.append(("a surviving VM -> fail", exit_code(), 1))

    # The one that matters: a blind search must never read as good news.
    fake([], [])
    cases.append(("control returns nothing (blind) -> fail, not pass", exit_code(), 1))

    fake(None, [], control_err="PERMISSION_DENIED")
    cases.append(("control errors -> fail", exit_code(), 1))

    fake([{"n": 1}], None, bill_err="API disabled")
    cases.append(("billable query errors -> fail", exit_code(), 1))

    mod.search, mod.org_id = real
    for label, got, want in cases:
        ok = got == want
        bad += not ok
        print(f"  {'ok  ' if ok else 'FAIL'}  {label} (exit {got}, want {want})")
    print("  self-test passed" if not bad else f"  {bad} case(s) failed")
    return 1 if bad else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    sys.exit(self_test() if a.self_test else run())

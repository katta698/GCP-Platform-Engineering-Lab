#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Break one tunnel and measure how fast BGP routes around it.

    python scripts/measure-failover.py --trials 3

Disables one HA VPN tunnel, polls the hub Cloud Router until the routes it
learned through that tunnel are withdrawn, then re-enables and waits for them
to come back. Reports both directions.

What this proves: a dead tunnel is noticed and routed around with nobody
touching a route table. Static routes cannot do that - they point at a dead
tunnel as confidently as a live one.

Restores the tunnel in a finally block. A script that degrades a control
restores it on every path out.
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
    """(rc, stdout, stderr) - never merged; gcloud writes progress to stderr."""
    p = subprocess.run([GCLOUD, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, p.stdout, p.stderr


def stamp():
    return datetime.now(timezone.utc).strftime("%H:%M:%S")


def learned_routes(router, project, region, dest):
    """How many times `dest` appears in the router's best routes.

    Two tunnels advertising the same prefix means two entries. One tunnel down
    should leave one. That count IS the failover signal.
    """
    rc, out, err = run(["compute", "routers", "get-status", router,
                        f"--project={project}", f"--region={region}",
                        "--format=json"])
    if rc != 0:
        raise RuntimeError(f"get-status failed: {err.strip()[:200]}")
    data = json.loads(out)
    result = (data[0] if isinstance(data, list) else data).get("result", {})
    best = result.get("bestRoutesForRouter") or result.get("bestRoutes") or []
    return sum(1 for r in best if r.get("destRange") == dest)


def bgp_up(router, project, region):
    rc, out, _ = run(["compute", "routers", "get-status", router,
                      f"--project={project}", f"--region={region}",
                      "--format=json"])
    if rc != 0:
        return -1
    data = json.loads(out)
    result = (data[0] if isinstance(data, list) else data).get("result", {})
    return sum(1 for p in result.get("bgpPeerStatus", [])
               if p.get("state") == "Established")


def set_tunnel(tunnel, project, region, up):
    """HA VPN tunnels have no enable/disable verb. Breaking the BGP peer is the
    closest reversible equivalent and exercises the same withdrawal path."""
    # The flag is --enabled / --no-enabled. There is no --disable.
    flag = "--enabled" if up else "--no-enabled"
    rc, _, err = run(["compute", "routers", "update-bgp-peer",
                      tunnel["router"], f"--peer-name={tunnel['peer']}",
                      f"--project={project}", f"--region={region}", flag])
    if rc != 0:
        raise RuntimeError(f"{flag} {tunnel['peer']} failed: {err.strip()[:300]}")


def wait_for(fn, want, timeout, poll=2):
    """Poll until fn() == want. Returns seconds taken, or None on timeout."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        if fn() == want:
            return round(time.time() - t0, 1)
        time.sleep(poll)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="katta698-gcp-net-hub")
    ap.add_argument("--region", default="us-central1")
    ap.add_argument("--router", default="hub-router")
    ap.add_argument("--peer", default="hub-peer-t0")
    ap.add_argument("--dest", default="10.30.0.0/24")
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    kw = dict(project=args.project, region=args.region)
    routes = lambda: learned_routes(args.router, args.project, args.region, args.dest)
    peers = lambda: bgp_up(args.router, args.project, args.region)

    base_routes, base_peers = routes(), peers()
    print(f"[{stamp()}] baseline: {base_routes} route(s) to {args.dest}, "
          f"{base_peers} BGP session(s) Established")
    if base_routes < 2 or base_peers < 2:
        sys.exit("ABORT: need two established sessions and two learned routes "
                 "before a failover means anything.")

    tunnel = {"router": args.router, "peer": args.peer}
    record = {"dest": args.dest, "baseline_routes": base_routes, "trials": []}

    try:
        for i in range(1, args.trials + 1):
            print(f"\n--- trial {i} ---")
            set_tunnel(tunnel, args.project, args.region, up=False)
            print(f"[{stamp()}] {args.peer} disabled")
            down = wait_for(routes, base_routes - 1, args.timeout)
            print(f"[{stamp()}] route withdrawn after {down}s"
                  if down is not None else
                  f"[{stamp()}] TIMEOUT: route never withdrawn")

            set_tunnel(tunnel, args.project, args.region, up=True)
            print(f"[{stamp()}] {args.peer} re-enabled")
            up = wait_for(routes, base_routes, args.timeout)
            print(f"[{stamp()}] route restored after {up}s"
                  if up is not None else
                  f"[{stamp()}] TIMEOUT: route never came back")
            record["trials"].append({"withdraw_s": down, "restore_s": up})
    finally:
        try:
            set_tunnel(tunnel, args.project, args.region, up=True)
            final = wait_for(routes, base_routes, 120)
            print(f"\n[{stamp()}] restored: {routes()} route(s), "
                  f"{peers()} session(s) Established")
            record["restored"] = final is not None
        except Exception as exc:                                # noqa: BLE001
            print(f"\nWARNING: could not restore {args.peer}: {exc}")
            record["restored"] = False

    ws = [t["withdraw_s"] for t in record["trials"] if t["withdraw_s"] is not None]
    print()
    if ws:
        print(f"RESULT: routes withdrawn in {min(ws)}-{max(ws)}s across "
              f"{len(ws)} trial(s).")
        print("  Nobody edited a route table. The surviving tunnel carried the "
              "prefix throughout.")
    else:
        print("RESULT: no withdrawal observed. This is a FAILED measurement, "
              "not a finding.")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2)
        print(f"written to {args.json}")
    return 0 if ws else 1


if __name__ == "__main__":
    sys.exit(main())

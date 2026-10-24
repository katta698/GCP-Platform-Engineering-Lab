#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create (or show) an HCP Terraform workspace in the right project, first time.

    python scripts/hcp_workspace.py --name gcp-week-10
    python scripts/hcp_workspace.py --name gcp-week-10 --show

Why this is a script and not a `terraform init`
-----------------------------------------------
`terraform init` creates a missing workspace in HCP's **Default Project**, not
in the project the rest of the lab lives in. That is what put `gcp-week-02`
outside `GCP Platform Lab` on 2026-08-25, and it also produced an execution mode
that appeared to ignore the UI: the workspace inherited Default Project's
default of `remote` with `setting-overwrites.execution-mode = false`, so setting
the radio button did not stick until that inheritance was broken.

Creating the workspace through the API with an explicit `project` relationship
puts it in the right place with the right execution mode on the first attempt.
Recorded as the fix on 2026-09-03 and done by hand for every week since, which
is eight hand-rolled API calls and the reason this file now exists.

Credentials
-----------
Read from the same place the Terraform CLI keeps them --
`%APPDATA%/terraform.d/credentials.tfrc.json` on Windows,
`~/.terraform.d/credentials.tfrc.json` elsewhere. The token is never printed,
never passed as an argument, and never written to the repo.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "app.terraform.io"
ORG = "Katta"
# The project every GCP week belongs to. Recorded in SESSION_CONTEXT.md; it is
# not a secret (it names no account and grants nothing) but it is also not
# guessable, so it is pinned here rather than looked up by display name, which
# would silently pick the wrong project if one were renamed.
PROJECT_ID = "prj-DfHkaPYnJgp5ejTA"
API = f"https://{HOST}/api/v2"


def token():
    base = (os.environ.get("APPDATA") and
            os.path.join(os.environ["APPDATA"], "terraform.d") or
            os.path.expanduser("~/.terraform.d"))
    path = os.path.join(base, "credentials.tfrc.json")
    if not os.path.exists(path):
        path = os.path.expanduser("~/.terraform.d/credentials.tfrc.json")
    if not os.path.exists(path):
        sys.exit(f"no HCP credentials at {path} - run: terraform login")
    with open(path, encoding="utf-8-sig") as fh:
        creds = json.load(fh)
    try:
        return creds["credentials"][HOST]["token"]
    except KeyError:
        sys.exit(f"credentials file has no token for {HOST} - run: terraform login")


def call(method, path, payload=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(payload).encode() if payload else None,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/vnd.api+json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"raw": body[:400]}


def describe(ws):
    a = ws["attributes"]
    proj = ws.get("relationships", {}).get("project", {}).get("data", {}).get("id", "?")
    print(f"  name            {a['name']}")
    print(f"  id              {ws['id']}")
    print(f"  execution mode  {a.get('execution-mode')}")
    print(f"  project         {proj}" +
          ("   <- GCP Platform Lab" if proj == PROJECT_ID else "   <- NOT the lab project"))
    print(f"  terraform ver   {a.get('terraform-version')}")
    print(f"  url             https://{HOST}/app/{ORG}/workspaces/{a['name']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="e.g. gcp-week-10")
    ap.add_argument("--show", action="store_true", help="report only; create nothing")
    args = ap.parse_args()

    status, body = call("GET", f"/organizations/{ORG}/workspaces/{args.name}")
    if status == 200:
        print(f"Workspace {args.name} already exists:")
        describe(body["data"])
        return 0
    if status != 404:
        sys.exit(f"unexpected {status} reading workspace: {json.dumps(body)[:300]}")

    if args.show:
        print(f"Workspace {args.name} does not exist.")
        return 1

    print(f"Creating {args.name} in project {PROJECT_ID}...")
    status, body = call("POST", f"/organizations/{ORG}/workspaces", {
        "data": {
            "type": "workspaces",
            "attributes": {
                "name": args.name,
                # Remote execution from the start. Every week since 05 runs on
                # HCP's machines with WIF dynamic credentials and no stored key.
                "execution-mode": "remote",
                "auto-apply": False,
            },
            "relationships": {
                "project": {"data": {"type": "projects", "id": PROJECT_ID}},
            },
        },
    })
    if status not in (200, 201):
        sys.exit(f"create failed {status}: {json.dumps(body)[:400]}")

    print("Created:")
    describe(body["data"])
    print("\nNext: set the workspace variables, then run the plan.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

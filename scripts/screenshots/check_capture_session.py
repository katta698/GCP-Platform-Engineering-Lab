#!/usr/bin/env python3
"""
Check EVERY session a week's screenshots will need, before the first apply.

    python scripts/screenshots/check_capture_session.py

Why this exists
---------------
The rule was already written down: check the capture session before the first
`terraform apply`, not after. On 2026-10-05 it was followed and still failed,
because "the capture session" was checked as two things that are easy to
confirm — the debug port answers, the profile directory exists — and those only
prove the browser is running.

They say nothing about whether it is still signed in, and nothing at all about
HCP Terraform, which has its own cookie that expires roughly daily. Week 08 was
built, deployed, validated and written up before anyone discovered the HCP
screenshot could not be taken. The ask then landed at the bottom of a long
message, which is not really asking.

So this checks what the screenshots actually need, by loading a page behind each
login and seeing where it lands.

The Google ADMIN CONSOLE is a third session, added 2026-10-23. It is NOT covered
by being signed in to the Google Cloud console: admin.google.com re-challenges
for a password even with a live Cloud console session on the same account, and
Week 10 found that out by trying to capture the Groups list and getting a sign-in
challenge instead. Any week touching Cloud Identity, groups, or Workspace admin
roles needs it, and those are exactly the weeks where the console is the only
surface - there is no gcloud for an Admin console page.

Exit code is 1 if anything a week needs is missing, so it can gate an apply.
"""

import sys

from playwright.sync_api import sync_playwright

CHECKS = [
    ("Google Cloud console", "https://console.cloud.google.com/billing",
     ("accounts.google.com", "/enable-mfa", "signin")),
    ("HCP Terraform",        "https://app.terraform.io/app/Katta/workspaces",
     ("/login", "/session")),
    # Separate from the Cloud console session - see the note above.
    ("Google Admin console", "https://admin.google.com/ac/groups",
     ("accounts.google.com", "signin", "challenge")),
]


def attach(pw, port=9222):
    """Attach to the capture Chrome, trying IPv4 and IPv6 on the same port.

    Three labs share this machine and all of them use 9222. On 2026-11-22 two
    Chromes were listening: this lab's capture profile on [::1] and another
    session's automation profile on 127.0.0.1. Connecting to 127.0.0.1 reached
    the wrong browser and failed with "Browser context management is not
    supported" - which reads like the capture Chrome is broken, when it was
    running and signed in the whole time.

    So try both, and accept the first that actually supports contexts.
    """
    errors = []
    for host in ("127.0.0.1", "[::1]"):
        try:
            b = pw.chromium.connect_over_cdp(f"http://{host}:{port}", timeout=60000)
            if b.contexts:
                return b, host
            errors.append(f"{host}: connected but has no browser context")
            b.close()
        except Exception as e:                                  # noqa: BLE001
            errors.append(f"{host}: {str(e)[:70]}")
    return None, errors


def main() -> int:
    bad = []
    with sync_playwright() as pw:
        browser, where = attach(pw)
        if browser is None:
            print("  CDP: DOWN")
            for line in where:
                print("    ", line)
            print("\n  Start it with scripts/screenshots/start-capture-chrome.bat")
            print("  If another lab's Chrome holds the port, this lab's may be")
            print("  on the other address - both are tried above.")
            return 1
        print(f"  CDP: up (on {where})")
        ctx = browser.contexts[0]
        for name, url, markers in CHECKS:
            page = ctx.new_page()
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=70000)
                page.wait_for_timeout(8000)
                landed = page.url
                ok = not any(m in landed for m in markers)
                print(f"  {name:22} {'signed in' if ok else 'SIGNED OUT -> ' + landed[:52]}")
                if not ok:
                    bad.append(name)
            except Exception as e:
                print(f"  {name:22} ERROR {str(e)[:50]}")
                bad.append(name)
            finally:
                page.close()

    if bad:
        print("\n  Sign in to the following in the capture Chrome, then re-run:")
        for b in bad:
            print(f"    - {b}")
        print("\n  Only a human can do this. There is no API path to a browser session,")
        print("  and the capture script refuses to save a login page - so a week that")
        print("  proceeds without this simply ends up missing those screenshots.")
        return 1

    print("\n  All sessions present. Safe to apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

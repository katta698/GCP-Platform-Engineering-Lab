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

So this checks what the screenshots actually need: both sessions, by loading a
page behind each login and seeing where it lands.

Exit code is 1 if anything a week needs is missing, so it can gate an apply.
"""

import sys

from playwright.sync_api import sync_playwright

CHECKS = [
    ("Google Cloud console", "https://console.cloud.google.com/billing",
     ("accounts.google.com", "/enable-mfa", "signin")),
    ("HCP Terraform",        "https://app.terraform.io/app/Katta/workspaces",
     ("/login", "/session")),
]


def main() -> int:
    bad = []
    with sync_playwright() as pw:
        try:
            browser = pw.chromium.connect_over_cdp("http://127.0.0.1:9222", timeout=60000)
        except Exception as e:
            print("  CDP: DOWN -", str(e)[:70])
            print("\n  Start it with scripts/screenshots/start-capture-chrome.bat")
            return 1
        print("  CDP: up")
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

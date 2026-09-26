#!/usr/bin/env python3
"""
Enable a Cloud Billing export to BigQuery without touching the console by hand.

Why this exists
---------------
Enabling a billing export is console-only. There is no gcloud command, no
Terraform resource, and no public REST endpoint — /v1/billingAccounts/{id}/
exportSettings returns 404, the provider schema lists nine google_billing_*
resources and no export among them, and Google's own billing-dashboard module
creates the datasets and then tells the operator to go and click.

"Console-only" describes the absence of an API. It does not describe the absence
of access. The same signed-in Chrome that takes this lab's screenshots can be
driven over the DevTools protocol, so the click is automatable even though the
action is not scriptable through any Google interface.

That distinction matters practically: the operator of this lab is usually on a
phone. A step that requires dragging a Windows desktop around through a remote
session is, in practice, a step that does not get done.

What it does NOT do
-------------------
It does not grant permissions. Configuring any export needs BOTH
billing.accounts.getPricing and billing.accounts.updateUsageExportSpec, and
those are split across roles — getPricing lives in billing.viewer and
billing.admin, not in billing.user or billing.costsManager. If the console
answers with a permission wall this script reports it and stops, because the fix
is a role grant made as a different identity:

    ./scripts/grant-billing-role.sh roles/billing.viewer

Usage
-----
    python scripts/enable_billing_export.py --kind pricing \\
        --project katta698-gcp-logging --dataset billing_pricing --cdp 9222

    # Look before leaping: dump the page's controls and change nothing.
    python scripts/enable_billing_export.py --kind pricing --dry-run --cdp 9222

BILLING_ACCOUNT is read from the environment so the ID never reaches a committed
file or a shell history entry.
"""

import argparse
import os
import re
import sys

from playwright.sync_api import sync_playwright

# The console labels each export by name; the button text is derived from it.
KINDS = {
    "standard": "standard",
    "detailed": "detailed",
    "pricing": "pricing",
    "focus": "FOCUS",
    "cud": "CUD",
}

PERMISSION_WALL = "do not have permissions to configure billing export"


def settle(page, ms: int) -> None:
    try:
        page.wait_for_load_state("networkidle", timeout=12000)
    except Exception:
        pass  # the console holds long-poll connections and never idles
    page.wait_for_timeout(ms)


def controls(page) -> list[str]:
    """Every interactive control, for --dry-run and for failure diagnosis."""
    out = []
    for sel in ("[role=combobox]", "select", "input", "button", "a.mdc-button"):
        for el in page.query_selector_all(sel):
            label = (
                (el.inner_text() or "").strip()
                or el.get_attribute("aria-label")
                or el.get_attribute("placeholder")
                or ""
            ).replace("\n", " ")
            if label and len(label) < 70:
                out.append(f"{sel:16} | {label}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", choices=sorted(KINDS), default="pricing")
    ap.add_argument("--project", help="Project holding the destination dataset")
    ap.add_argument("--dataset", help="Destination dataset ID")
    ap.add_argument("--cdp", default="9222")
    ap.add_argument("--wait-ms", type=int, default=16000)
    ap.add_argument("--dry-run", action="store_true", help="Inspect only; click nothing")
    args = ap.parse_args()

    account = os.environ.get("BILLING_ACCOUNT", "").strip()
    if not account:
        sys.exit("set BILLING_ACCOUNT (it is a secret; it is not read from a committed file)")
    if not args.dry_run and not (args.project and args.dataset):
        sys.exit("--project and --dataset are required unless --dry-run")

    url = f"https://console.cloud.google.com/billing/{account}/export/bigquery"

    with sync_playwright() as pw:
        browser = pw.chromium.connect_over_cdp(f"http://127.0.0.1:{args.cdp}", timeout=90000)
        page = browser.contexts[0].new_page()
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=75000)
            settle(page, args.wait_ms)

            if "enable-mfa" in page.url:
                sys.exit(
                    "Console is blocked pending 2-step verification.\n"
                    "  Google began enforcing 2SV for console access on 2026-09-21.\n"
                    "  gcloud and Terraform are unaffected; only the console is gated."
                )

            body = page.inner_text("body")

            # Report current state before changing it. The single most useful
            # thing this script ever printed was that an export nobody knew
            # about had been running since July.
            # The console renders the status on the line AFTER the section
            # heading, so a per-line match prints the names and drops the one
            # fact worth printing. Pair each heading with its next non-empty
            # line instead.
            print("== Current export state ==")
            lines = [ln.strip() for ln in body.split("\n")]
            headings = (
                "Standard usage cost",
                "Detailed usage cost",
                "Pricing",
                "FOCUS usage cost",
                "Committed Use Discounts Export",
            )
            for i, ln in enumerate(lines):
                if ln in headings or any(ln.startswith(h) for h in headings):
                    status = next(
                        (s for s in lines[i + 1 : i + 4] if s in ("Enabled", "Disabled")),
                        "?",
                    )
                    print(f"  {status:9} {ln}")
            print()

            if args.dry_run:
                print("== Controls on the page ==")
                for c in controls(page):
                    print("  " + c)
                return

            label = f"Enable {KINDS[args.kind]} export"
            # These are <a class="mdc-button">, not <button>, so a role-based
            # lookup finds nothing. Match on text instead.
            target = page.query_selector(f"text={label}")
            if target is None:
                print(f"No '{label}' control found. Either it is already enabled, or:")
                for c in controls(page):
                    print("  " + c)
                sys.exit(1)

            print(f"== Clicking '{label}' ==")
            target.click()
            settle(page, 9000)

            body = page.inner_text("body")
            if PERMISSION_WALL in body:
                sys.exit(
                    "Refused: the signed-in account cannot configure billing export.\n"
                    "  Configuring an export needs BOTH of:\n"
                    "    billing.accounts.getPricing          (billing.viewer / billing.admin)\n"
                    "    billing.accounts.updateUsageExportSpec (billing.user / costsManager)\n"
                    "  Fix with:  ./scripts/grant-billing-role.sh roles/billing.viewer\n"
                    "  That grant must be made as the identity holding billing.admin."
                )

            print("== Form controls now on screen ==")
            for c in controls(page):
                print("  " + c)
            print()
            print("Select the project and dataset in the panel above, then Save.")
            print(f"Target: project={args.project} dataset={args.dataset}")
            print()
            print("Verify afterwards with:")
            print(f"  bq ls --project_id={args.project} {args.dataset}")
        finally:
            page.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Capture a blog screenshot of a Google Cloud console (or HCP Terraform) page.

Why this exists rather than reusing the AWS lab's capture.py:

  1. Its redaction only knows about AWS account IDs. A Google Cloud console page
     renders organization IDs, project numbers and billing account IDs, and none
     of those would be masked — they would go straight into a published post.
  2. It navigates with wait_until="load" and a hard 30s cap. The Cloud console
     holds long-poll connections open and never fires `load`, so every capture
     times out. This one waits for "domcontentloaded" and then settles.

Everything else follows the same discipline as the AWS script, for the same
reasons it was learned there: never save a sign-in page, and assert the secrets
are gone *after* redacting rather than trusting the redaction ran.

Authentication is not handled here. Sign in yourself in the Chrome that
`start-capture-chrome.bat` opens, then attach to it with --cdp. No password ever
passes through this script.

Usage:
  python capture_gcp.py <url> <output.png> --cdp 9222 [--wait-ms 9000] [--height 1000]

Identifiers to mask are read from the environment so they never appear in shell
history or in this file:
  GCP_ORG_ID, GCP_BILLING_ACCOUNT, GCP_PROJECT_NUMBERS (comma-separated)
"""

import argparse
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

MASK = "█" * 12


def secrets_from_env() -> list[tuple[str, str]]:
    """Identifier -> label pairs to mask. Missing ones are simply skipped."""
    out = []
    if org := os.environ.get("GCP_ORG_ID", "").strip():
        out.append((org, "organization ID"))
    if bill := os.environ.get("GCP_BILLING_ACCOUNT", "").strip():
        out.append((bill, "billing account ID"))
    for num in os.environ.get("GCP_PROJECT_NUMBERS", "").split(","):
        if num := num.strip():
            out.append((num, "project number"))
    return out


def settle(page) -> None:
    """Let navigation finish before touching the DOM.

    A redaction pass is a page.evaluate(), and evaluate() throws if a navigation
    lands mid-call. The Cloud console redirects after load more often than not
    (project picker, consent, ?pli=1), so settling first is not optional.
    """
    try:
        page.wait_for_load_state("networkidle", timeout=12000)
    except Exception:
        pass  # never settles on long-poll pages; the explicit wait below covers it
    page.wait_for_timeout(800)


# Hosts and paths that only ever serve authentication. Landing on one means the
# session is not there, whatever the page happens to render.
LOGIN_HOSTS = ("accounts.google.com", "signin.aws.amazon.com")
LOGIN_PATHS = ("/login", "/signin", "/servicelogin", "/sso/saml")


def assert_not_a_login_page(page) -> None:
    """Refuse to save a sign-in screen.

    The leak assertions answer "did anything escape", not "did we capture the
    page we asked for". A login page passes them all trivially — it contains
    nothing. The AWS lab shipped two identical pictures of an HCP login form in
    Week 15 for exactly this reason, and this script reproduced the same failure
    on 2026-08-21, before the URL check below existed.

    The URL is the reliable signal. Google's sign-in page renders "Sign in" in a
    plain div rather than an h1, and its title lags the redirect, so a DOM-text
    check alone misses it — which is precisely how the bad capture got through.
    Content checks are kept as a second layer, not the first.
    """
    url = page.url or ""
    low = url.lower()
    if any(h in low for h in LOGIN_HOSTS) or any(p in low for p in LOGIN_PATHS):
        sys.exit(
            f"REFUSING TO SAVE: redirected to an authentication URL.\n"
            f"  landed on: {url}\n"
            f"  Fix: sign in to this service in the Chrome on the --cdp port, then retry."
        )

    hit = page.evaluate(
        """() => {
            if (document.querySelector('input[type=password]')) return 'password field';
            if (document.querySelector('input[type=email]')) return 'email field';
            const t = (document.title || '').toLowerCase();
            if (t.includes('sign in') || t.includes('log in')) return 'title: ' + document.title;
            const text = (document.body ? document.body.innerText : '').trim().toLowerCase();
            for (const p of ['sign in', 'log in', 'choose an account', 'forgot email']) {
                if (text.startsWith(p)) return 'body starts with: ' + p;
            }
            return null;
        }"""
    )
    if hit:
        sys.exit(
            f"REFUSING TO SAVE: this looks like a sign-in page ({hit}).\n"
            f"  Fix: sign in inside the Chrome on the --cdp port, then retry."
        )


def assert_not_an_error_page(page) -> None:
    """Refuse to save a 404 or a permission wall.

    The console answers a bad URL with a styled page inside the normal chrome —
    same nav, same header, same everything but the content. A capture of it looks
    like a real screenshot at a glance and is only caught by reading the words,
    which nobody does when reviewing sixty images before publishing.

    Cheaper to fail here than to publish a picture of "URL not found" captioned
    as a custom constraint.
    """
    body = page.inner_text("body")[:4000]
    # "Requested constraint not found" is a TOAST, not a page. The console
    # silently returns to the list underneath it, so the capture looks like a
    # perfectly good screenshot of the wrong page — the failure that produced
    # this line was exactly that.
    for marker in ("URL not found", "We couldn't find what you were looking for",
                   "You don't have permission", "Error 404",
                   "Requested constraint not found", "not found"):
        if marker in body:
            raise SystemExit(f"refusing to save: page shows {marker!r} — {page.url}")


def click_text(page, text: str, settle_ms: int = 6000) -> None:
    """Click the first visible element whose text contains `text`, then settle.

    Failure is loud rather than silent. A missed click produces a screenshot of
    the wrong view that still looks plausible — the unfiltered list rather than
    the filtered one — and that is far worse than no screenshot, because it gets
    published as evidence of something it does not show.
    """
    for sel in (f"button:has-text('{text}')", f"a:has-text('{text}')", f"text={text}"):
        try:
            el = page.locator(sel).first
            if el.count() and el.is_visible():
                el.click(timeout=10000)
                settle(page)
                page.wait_for_timeout(settle_ms)
                return
        except Exception:
            continue
    raise SystemExit(f"click-text: nothing visible matching {text!r} — refusing to capture the wrong view")


def expand_tree(page, rounds: int = 4) -> None:
    """Expand every collapsed row in the Manage resources tree.

    The page loads with folders collapsed, so a straight capture shows the org
    and its top-level folders and nothing beneath — hiding the nesting that a
    hierarchy screenshot exists to demonstrate.

    Looped rather than done once: expanding a folder reveals child folders that
    were not in the DOM before, and those start collapsed too. It stops early
    when a pass finds nothing left to click.

    Scoped to the table on purpose. A bare [aria-expanded="false"] selector also
    matches the console's left navigation, and clicking those navigates away from
    the page entirely — on 2026-08-21 it landed on org Settings and captured the
    wrong screen. Restricting to rows inside a table, and re-asserting the URL
    afterwards, keeps that from happening silently.
    """
    before = page.url
    for _ in range(rounds):
        toggles = page.locator('table [aria-expanded="false"], [role="treegrid"] [aria-expanded="false"]')
        n = toggles.count()
        if n == 0:
            break
        for i in range(n):
            try:
                toggles.nth(i).click(timeout=3000)
                page.wait_for_timeout(400)
            except Exception:
                pass  # row re-rendered under us; the next pass picks it up
        page.wait_for_timeout(1200)

    if page.url.split("?")[0] != before.split("?")[0]:
        sys.exit(
            f"REFUSING TO SAVE: expanding the tree navigated away.\n"
            f"  from: {before}\n"
            f"  to:   {page.url}"
        )


def redact(page, secrets: list[tuple[str, str]]) -> None:
    """Replace each identifier in every text node, and in value/title/aria attributes."""
    if not secrets:
        return
    page.evaluate(
        """([pairs, mask]) => {
            const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            const nodes = [];
            while (walk.nextNode()) nodes.push(walk.currentNode);
            for (const n of nodes) {
                let v = n.nodeValue;
                for (const [needle] of pairs) if (v.includes(needle)) v = v.split(needle).join(mask);
                if (v !== n.nodeValue) n.nodeValue = v;
            }
            for (const el of document.querySelectorAll('[value],[title],[aria-label]')) {
                for (const attr of ['value', 'title', 'aria-label']) {
                    const cur = el.getAttribute(attr);
                    if (!cur) continue;
                    let v = cur;
                    for (const [needle] of pairs) if (v.includes(needle)) v = v.split(needle).join(mask);
                    if (v !== cur) el.setAttribute(attr, v);
                }
            }
            // Form controls render the `value` PROPERTY, not the attribute, and
            // the two are independent once the page has scripted the field. The
            // Cloud console's org Settings page puts the organization ID in a
            // read-only <input>, which the attribute pass above leaves untouched
            // and which innerText never sees — that combination leaked an org ID
            // to disk on 2026-08-21.
            for (const el of document.querySelectorAll('input, textarea')) {
                let v = el.value;
                if (typeof v !== 'string' || !v) continue;
                for (const [needle] of pairs) if (v.includes(needle)) v = v.split(needle).join(mask);
                if (v !== el.value) el.value = v;
            }
        }""",
        [secrets, MASK],
    )


def assert_gone(page, secrets: list[tuple[str, str]]) -> None:
    """Last line of defence: fail loudly rather than write a leaking PNG.

    Scans form-control values as well as innerText. innerText alone is not
    enough — it excludes <input> values, so a read-only field showing an
    organization ID passes an innerText check while rendering the ID in plain
    sight. That is exactly how a leak reached disk on 2026-08-21.
    """
    visible = page.evaluate(
        """() => {
            let s = document.body ? document.body.innerText : '';
            for (const el of document.querySelectorAll('input, textarea')) {
                if (typeof el.value === 'string') s += '\\n' + el.value;
                const a = el.getAttribute('value');
                if (a) s += '\\n' + a;
            }
            return s;
        }"""
    )
    for needle, label in secrets:
        if needle in visible:
            sys.exit(f"REFUSING TO SAVE: {label} still visible after redaction.")


def screenshot_via_cdp(page, out: Path) -> None:
    """Capture through the DevTools protocol rather than page.screenshot().

    page.screenshot() waits for the page to stop changing before it fires. The
    Cloud console never stops changing — it holds long-poll connections and
    repaints continuously — so the call hangs for its whole timeout and then
    fails having written nothing. `animations="disabled"` does not help, because
    the instability is network-driven repaint, not CSS animation.

    Page.captureScreenshot has no stability heuristic. It grabs the frame as it
    is, which is all a blog screenshot needs.
    """
    import base64

    client = page.context.new_cdp_session(page)
    try:
        result = client.send("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": False})
        out.write_bytes(base64.b64decode(result["data"]))
    finally:
        try:
            client.detach()
        except Exception:
            pass


def clear_stale(out: Path) -> None:
    """Delete any previous file at this path before attempting a capture.

    Every guard in this script refuses to SAVE. None of them delete, so a refused
    run leaves the previous attempt's file sitting at the output path, with a
    fresh-looking timestamp from whenever it was written. The reviewer sees a
    file where they expected one and moves on.

    Removing it first makes a refusal visible as an absence, which is the only
    honest outcome of a capture that did not happen.
    """
    try:
        out.unlink()
    except FileNotFoundError:
        pass


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("output_path")
    ap.add_argument("--cdp", type=int, required=True, help="Port of the already-signed-in Chrome")
    ap.add_argument("--wait-ms", type=int, default=8000, help="Settle time after load")
    ap.add_argument("--height", type=int, default=1000)
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--goto-timeout", type=int, default=60000)
    ap.add_argument("--full-page", action="store_true")
    ap.add_argument(
        "--click-text",
        action="append",
        default=[],
        help=(
            "Click the first clickable element whose text contains this string, "
            "then wait, then capture. The console's useful views are often behind "
            "a button rather than a URL — 'View dry-run policies' filters the "
            "list to the five that matter out of nearly two hundred, and there is "
            "no query parameter that does the same."
        ),
    )
    ap.add_argument(
        "--expand-tree",
        action="store_true",
        help=(
            "Click every collapsed row toggle before capturing. The Manage "
            "resources page loads with folders collapsed, which hides the very "
            "thing a hierarchy screenshot is meant to show."
        ),
    )
    args = ap.parse_args()

    secrets = secrets_from_env()
    if not secrets:
        print("NOTE: no GCP_* identifiers set, nothing will be masked.")

    out = Path(args.output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as pw:
        browser = pw.chromium.connect_over_cdp(f"http://127.0.0.1:{args.cdp}")
        context = browser.contexts[0]
        page = context.new_page()
        page.set_viewport_size({"width": args.width, "height": args.height})
        try:
            # "load" never fires on the Cloud console — it holds long-poll
            # connections open indefinitely. domcontentloaded plus an explicit
            # settle is what actually works.
            clear_stale(out)
            page.goto(args.url, wait_until="domcontentloaded", timeout=args.goto_timeout)
            settle(page)
            page.wait_for_timeout(args.wait_ms)

            assert_not_a_login_page(page)
            assert_not_an_error_page(page)

            if args.expand_tree:
                expand_tree(page)

            # Clicking happens BEFORE redaction, not after. A click can trigger a
            # fetch that repaints the table, and a repaint restores the original
            # text — so redacting first would put the identifiers back on screen
            # in the frame that gets saved.
            # Repeatable, and applied in order. Some views are two clicks deep:
            # the dry-run filter narrows nearly two hundred constraints to four,
            # and only then is the custom constraint's link on screen to open.
            for t in args.click_text:
                click_text(page, t)

            redact(page, secrets)
            assert_gone(page, secrets)

            # Checked twice on purpose. A session can lapse and redirect between
            # the first check and the save, and the screenshot is what reaches
            # disk — so the guard that matters is the one closest to it.
            assert_not_a_login_page(page)
            screenshot_via_cdp(page, out)
            masked = ", ".join(sorted({label for _, label in secrets})) or "nothing"
            print(f"Verified: masked {masked}")
            print(f"Saved: {out}")
        finally:
            # The browser belongs to the user. Close only the tab we opened.
            try:
                page.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()

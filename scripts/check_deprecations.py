#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Every service a week uses must have its deprecation status read, not inferred.

    python scripts/check_deprecations.py week-13-hybrid-connectivity
    python scripts/check_deprecations.py week-13-... --online   # fetch each URL
    python scripts/check_deprecations.py --self-test

Week 13 published the claim "Classic VPN is not deprecated". It came from
reading the product overview page and seeing no deprecation banner. Google
keeps deprecations on their own pages: dynamic routing (BGP) for Classic VPN
was deprecated on 2025-08-01, and the overview does not say so. The claim was
true about the product and wrong about the only capability the week was about.

Absence of a notice on the page you happened to open is not evidence of
absence. The Pre-Build Briefing asks whether a service "is not superseded" -
this makes answering it produce a citation instead of an impression.

THE FILE - <week>/docs/deprecations.md, one row per service:

    | Service | Deprecation page consulted | Checked | Status |
    | --- | --- | --- | --- |
    | HA VPN | https://docs.cloud.google.com/.../deprecations/... | 2026-11-15 | current |
    | Cloud Router | https://.../deprecations/classic-vpn-deprecation | 2026-11-15 | BGP on Classic VPN deprecated 2025-08-01; HA VPN unaffected |

A row needs a real URL, a date, and a status in the author's own words. "none
found" is not a status - say which index was searched and what it returned.

Run it at the briefing, and again on publish day: a status read six weeks ago
is an impression again.
"""
import argparse
import datetime as dt
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_AGE_DAYS = 14          # older than a fortnight is a fresh look, not a recall
VAGUE = ("none", "n/a", "na", "-", "none found", "ok", "fine", "current?")


def rows(path):
    """[(service, url, date, status), ...] from the markdown table."""
    if not os.path.exists(path):
        return None
    out = []
    for line in open(path, encoding="utf-8"):
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        if cells[0].lower() in ("service", "---") or set(cells[0]) <= {"-", " "}:
            continue
        out.append(tuple(cells[:4]))
    return out


def services_in_readme(week_dir):
    """Service names from the week README's 'What it builds' table, lowercased.

    Best effort on purpose: this check exists to make the author name the
    services, not to parse prose perfectly. It only ever ADDS things to look
    for, and a service it misses is one the author still has to list.
    """
    p = os.path.join(week_dir, "README.md")
    if not os.path.exists(p):
        return set()
    found = set()
    for line in open(p, encoding="utf-8"):
        for m in re.finditer(r"\b(HA VPN|Classic VPN|Cloud Router|Cloud VPN|"
                             r"Secret Manager|Cloud KMS|Pub/Sub|BigQuery|"
                             r"Cloud Logging|Shared VPC|Compute Engine|"
                             r"Cloud Asset Inventory|Privileged Access Manager|"
                             r"Cloud Identity|Org Policy|Cloud Functions|"
                             r"Cloud Run)\b", line):
            found.add(m.group(1).lower())
    return found


def check(week_dir, today=None, online=False):
    today = today or dt.date.today()
    name = os.path.basename(week_dir.rstrip("/\\"))
    path = os.path.join(week_dir, "docs", "deprecations.md")
    table = rows(path)
    if table is None:
        return [f"{name}: docs/deprecations.md is missing. Every service the "
                f"week uses needs its deprecation page read and cited."]
    if not table:
        return [f"{name}: docs/deprecations.md has no service rows."]

    fails = []
    listed = {r[0].strip().lower() for r in table}
    for svc in sorted(services_in_readme(week_dir) - listed):
        fails.append(f"{name}: the README names {svc!r} but deprecations.md "
                     f"has no row for it")

    for svc, url, date, status in table:
        if not re.match(r"https?://\S+", url):
            fails.append(f"{name}/{svc}: no deprecation page cited "
                         f"(got {url!r}). Name the index you searched.")
        if status.strip().lower() in VAGUE or len(status.strip()) < 12:
            fails.append(f"{name}/{svc}: status {status!r} says nothing. "
                         f"Record what the page actually said.")
        try:
            d = dt.datetime.strptime(date.strip(), "%Y-%m-%d").date()
        except ValueError:
            fails.append(f"{name}/{svc}: {date!r} is not a YYYY-MM-DD date")
            continue
        age = (today - d).days
        if age > MAX_AGE_DAYS:
            fails.append(f"{name}/{svc}: checked {age} days ago "
                         f"(limit {MAX_AGE_DAYS}). Re-read it before publishing.")
        if age < 0:
            fails.append(f"{name}/{svc}: checked date {d} is in the future")

    if online:
        try:
            import urllib.request
            for svc, url, _d, _s in table:
                if not url.startswith("http"):
                    continue
                try:
                    req = urllib.request.Request(url, method="HEAD",
                                                 headers={"User-Agent": "lab-check"})
                    urllib.request.urlopen(req, timeout=20)
                except Exception as exc:                        # noqa: BLE001
                    fails.append(f"{name}/{svc}: cited page did not answer "
                                 f"({exc.__class__.__name__}) - {url}")
        except ImportError:
            pass
    return fails


def run(week_dir, online=False, quiet=False):
    fails = check(week_dir, online=online)
    if not quiet:
        for f in fails:
            print(f"  FAIL  {f}")
        if not fails:
            print("  every service has a cited, recent deprecation check")
    return 1 if fails else 0


# ---------------------------------------------------------------------------

def self_test():
    import shutil
    import tempfile
    tmp = tempfile.mkdtemp()
    TODAY = dt.date(2026, 11, 15)
    try:
        def build(table=None, readme="Uses **HA VPN** and Cloud Router.\n"):
            d = os.path.join(tmp, "week-99-x")
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(os.path.join(d, "docs"))
            open(os.path.join(d, "README.md"), "w", encoding="utf-8").write(readme)
            if table is not None:
                open(os.path.join(d, "docs", "deprecations.md"), "w",
                     encoding="utf-8").write(table)
            return d

        HEAD = ("| Service | Page | Checked | Status |\n| --- | --- | --- | --- |\n")
        GOOD = (HEAD +
                "| HA VPN | https://docs.cloud.google.com/a | 2026-11-14 | "
                "no deprecation listed on the VPN deprecations index |\n"
                "| Cloud Router | https://docs.cloud.google.com/b | 2026-11-14 | "
                "BGP on Classic VPN deprecated 2025-08-01; HA VPN unaffected |\n")
        cases = []

        d = build(GOOD)
        cases.append(("all services cited and recent",
                      1 if check(d, TODAY) else 0, 0))

        d = build(None)
        cases.append(("deprecations.md missing",
                      1 if check(d, TODAY) else 0, 1))

        # The real Week 13 failure: a service used but never looked up.
        d = build(HEAD + "| HA VPN | https://x.dev/a | 2026-11-14 | "
                         "nothing on the deprecations index |\n")
        cases.append(("a used service has no row",
                      1 if check(d, TODAY) else 0, 1))

        d = build(HEAD + "| HA VPN | none | 2026-11-14 | nothing listed anywhere |\n"
                         "| Cloud Router | https://x.dev/b | 2026-11-14 | "
                         "nothing on the deprecations index |\n")
        cases.append(("no page cited, only an assertion",
                      1 if check(d, TODAY) else 0, 1))

        d = build(HEAD + "| HA VPN | https://x.dev/a | 2026-11-14 | none |\n"
                         "| Cloud Router | https://x.dev/b | 2026-11-14 | "
                         "nothing on the deprecations index |\n")
        cases.append(("status says 'none' and nothing else",
                      1 if check(d, TODAY) else 0, 1))

        d = build(HEAD + "| HA VPN | https://x.dev/a | 2026-09-01 | "
                         "nothing on the deprecations index |\n"
                         "| Cloud Router | https://x.dev/b | 2026-11-14 | "
                         "nothing on the deprecations index |\n")
        cases.append(("checked 75 days ago",
                      1 if check(d, TODAY) else 0, 1))

        d = build(HEAD + "| HA VPN | https://x.dev/a | 14-11-2026 | "
                         "nothing on the deprecations index |\n"
                         "| Cloud Router | https://x.dev/b | 2026-11-14 | "
                         "nothing on the deprecations index |\n")
        cases.append(("date not ISO", 1 if check(d, TODAY) else 0, 1))

        bad = 0
        for label, got, want in cases:
            ok = got == want
            bad += not ok
            print(f"  {'ok  ' if ok else 'FAIL'}  {label} (got {got}, want {want})")
        print("  self-test passed" if not bad else f"  {bad} case(s) failed")
        return 1 if bad else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?")
    ap.add_argument("--online", action="store_true",
                    help="also confirm each cited page still answers")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        sys.exit(self_test())
    if not a.week:
        ap.error("give a week folder, or --self-test")
    sys.exit(run(a.week, online=a.online))

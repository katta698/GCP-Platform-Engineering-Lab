#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A figure the plan calls perishable must be captured at the deploy, not later.

    python scripts/check_capture_timing.py <week-folder>
    python scripts/check_capture_timing.py --self-test

Week 13 declared, in its own figure plan: "02 and 03 first, before anything is
broken." The deploy ran at 06:58. Those figures were made at 16:35, four minutes
before teardown, in one batch with everything else. Every check passed, because
`check_figures_before_destroy.py` asks whether a figure EXISTS when you destroy
and a last-minute batch satisfies that exactly.

Existence is the wrong question for a perishable view. The right one is whether
it was taken while the state it claims was still the live state.

HOW IT KNOWS
    `terraform apply` is followed by writing a marker:
        date -u +%Y-%m-%dT%H:%M:%SZ > docs/evidence/_deployed.txt
    and each capture tees its real output into docs/evidence/<slot>.txt with
    its own UTC stamp on the first line:
        { date -u +'# captured %Y-%m-%dT%H:%M:%SZ'; gcloud ... ; } \
            | tee docs/evidence/02-tunnels-up.txt

A perishable slot whose capture is more than WINDOW_MIN minutes after the
deploy marker fails. That is not a style rule - a view taken nine hours late is
a reconstruction, and the whole reason the slot was marked perishable is that
the state does not survive the week.
"""
import argparse
import datetime as dt
import os
import re
import sys

WINDOW_MIN = 90          # generous: an apply plus settling, not half a day
STAMP = re.compile(r"#\s*captured\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)")


def _parse(s):
    return dt.datetime.strptime(s.strip(), "%Y-%m-%dT%H:%M:%SZ")


def perishable_slots(plan_path):
    """Slot file names whose row marks the view perishable.

    The marker is the word itself in the row - the plans already write
    "**perishable**" in the Stated check column, so nothing new is required
    of the author.
    """
    if not os.path.exists(plan_path):
        return []
    out = []
    for line in open(plan_path, encoding="utf-8"):
        if "perishable" not in line.lower() or not line.strip().startswith("|"):
            continue
        m = re.search(r"`([\w.-]+\.png)`", line)
        if m:
            out.append(m.group(1))
    return out


def check(week_dir, window_min=WINDOW_MIN):
    """[] when clean, else a list of failures. Silent when nothing is declared."""
    docs = os.path.join(week_dir, "docs")
    slots = perishable_slots(os.path.join(docs, "FIGURE_PLAN.md"))
    if not slots:
        return []

    ev = os.path.join(docs, "evidence")
    marker = os.path.join(ev, "_deployed.txt")
    if not os.path.exists(marker):
        return [f"{len(slots)} perishable slot(s) declared but "
                f"docs/evidence/_deployed.txt is missing, so there is nothing "
                f"to time the captures against"]
    try:
        deployed = _parse(open(marker, encoding="utf-8").read())
    except ValueError:
        return ["docs/evidence/_deployed.txt is not an ISO UTC timestamp"]

    fails = []
    for slot in slots:
        cap = os.path.join(ev, os.path.splitext(slot)[0] + ".txt")
        if not os.path.exists(cap):
            fails.append(f"{slot}: perishable, but no capture at "
                         f"docs/evidence/{os.path.basename(cap)}")
            continue
        m = STAMP.search(open(cap, encoding="utf-8", errors="replace").read())
        if not m:
            fails.append(f"{slot}: capture has no '# captured <UTC>' first line, "
                         f"so when it was taken cannot be established")
            continue
        late = (_parse(m.group(1)) - deployed).total_seconds() / 60.0
        if late > window_min:
            fails.append(f"{slot}: captured {late:.0f} min after the deploy "
                         f"(limit {window_min}). A perishable view taken this "
                         f"late is a reconstruction, not an observation")
        elif late < -5:
            fails.append(f"{slot}: captured {-late:.0f} min BEFORE the deploy")
    return fails


def run(week_dir, quiet=False):
    fails = check(week_dir)
    if not quiet:
        slots = perishable_slots(os.path.join(week_dir, "docs", "FIGURE_PLAN.md"))
        if not slots:
            print("  no perishable slots declared; nothing to time")
        else:
            print(f"  {len(slots)} perishable slot(s): {', '.join(slots)}")
            for f in fails:
                print(f"  FAIL  {f}")
            if not fails:
                print("  every perishable view was captured at the deploy")
    return 1 if fails else 0


# ---------------------------------------------------------------------------

def self_test():
    import shutil
    import tempfile
    tmp = tempfile.mkdtemp()
    try:
        def build(plan, deployed=None, captures=()):
            d = os.path.join(tmp, "week-99-x")
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(os.path.join(d, "docs", "evidence"))
            open(os.path.join(d, "docs", "FIGURE_PLAN.md"), "w",
                 encoding="utf-8").write(plan)
            if deployed:
                open(os.path.join(d, "docs", "evidence", "_deployed.txt"), "w",
                     encoding="utf-8").write(deployed)
            for name, body in captures:
                open(os.path.join(d, "docs", "evidence", name), "w",
                     encoding="utf-8").write(body)
            return d

        PLAN = ("| # | File | Method | Shows | Stated check |\n"
                "| 02 | `02-tunnels-up.png` | console | four tunnels | "
                "**perishable** - gone once slot 05 runs |\n"
                "| 04 | `04-routes.png` | terminal | routes | the route exists |\n")
        DEP = "2026-11-14T12:58:00Z\n"
        cases = []

        d = build(PLAN, DEP, [("02-tunnels-up.txt",
                               "# captured 2026-11-14T13:10:00Z\nNAME\n")])
        cases.append(("captured 12 min after deploy", run(d, True), 0))

        # The real Week 13 shape: nine hours late, minutes before teardown.
        d = build(PLAN, DEP, [("02-tunnels-up.txt",
                               "# captured 2026-11-14T22:35:00Z\nNAME\n")])
        cases.append(("captured 9h later, just before teardown", run(d, True), 1))

        d = build(PLAN, DEP, [("02-tunnels-up.txt", "NAME\nno stamp\n")])
        cases.append(("capture carries no timestamp", run(d, True), 1))

        d = build(PLAN, DEP)
        cases.append(("perishable slot never captured", run(d, True), 1))

        d = build(PLAN)
        cases.append(("no deploy marker written", run(d, True), 1))

        d = build("| 04 | `04-routes.png` | terminal | routes | it exists |\n", DEP)
        cases.append(("week declares nothing perishable", run(d, True), 0))

        d = build(PLAN, DEP, [("02-tunnels-up.txt",
                               "# captured 2026-11-14T11:00:00Z\nNAME\n")])
        cases.append(("captured before the deploy", run(d, True), 1))

        bad = 0
        for label, got, want in cases:
            ok = got == want
            bad += not ok
            print(f"  {'ok  ' if ok else 'FAIL'}  {label} (exit {got}, want {want})")
        print("  self-test passed" if not bad else f"  {bad} case(s) failed")
        return 1 if bad else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        sys.exit(self_test())
    if not a.week:
        ap.error("give a week folder, or --self-test")
    sys.exit(run(a.week))

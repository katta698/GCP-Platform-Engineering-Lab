#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The roadmap table must agree with what is actually on disk.

    python scripts/check_roadmap_status.py
    python scripts/check_roadmap_status.py --self-test

Why this exists
---------------
README.md's roadmap carries a Status column, and nothing kept it honest. On
2026-10-24 Jay opened the repo on his phone and found Weeks 06 and 07 marked
"Planned". Both had been deployed and published a month earlier, and so had 08,
09 and 10 - five consecutive weeks wrong, on the first table a visitor sees.

Every one of those weeks ended with a session that updated SESSION_CONTEXT.md
and the week's own README and never touched the roadmap. The convention existed
(Weeks 01-05 are all marked Complete, with a folder link) and was simply not
carried forward, which is the same shape as the "What You Need to Know"
inventory the blog repo lost at Week 03: a standard visible in the early weeks
and dropped silently later.

Jay should not be the thing that notices.

What it asserts
---------------
A week whose folder contains `terraform/main.tf` is DEPLOYED, and the roadmap
row for that week number must say Complete and must link to the folder. A week
with no folder must not claim Complete.

Deliberately NOT checked: whether the blog post is published. That lives in
another repository, this script runs offline, and conflating "built" with
"published" is how a status column starts lying in the other direction.
"""
import argparse
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "README.md")

# | [06](./week-06-billing-export) | title | services | ✅ Complete |
ROW_RE = re.compile(r"^\|\s*(?:\[(\d{2})\]\(([^)]*)\)|(\d{2}))\s*\|.*?\|\s*(.*?)\s*\|\s*$", re.M)


def deployed_weeks():
    """Week numbers whose folder carries terraform/main.tf."""
    found = {}
    for name in os.listdir(ROOT):
        m = re.match(r"^week-(\d{2})-", name)
        if not m:
            continue
        if os.path.exists(os.path.join(ROOT, name, "terraform", "main.tf")):
            found[m.group(1)] = name
    return found


def audit(text, deployed):
    """Return a list of problem strings. Pure, so --self-test can prove it."""
    problems = []
    for m in ROW_RE.finditer(text):
        num = m.group(1) or m.group(3)
        link = m.group(2) or ""
        status = m.group(4)
        complete = "Complete" in status
        if num in deployed:
            if not complete:
                problems.append(
                    f"week {num}: {deployed[num]}/terraform/main.tf exists but the "
                    f"roadmap says {status!r}")
            elif deployed[num] not in link:
                problems.append(
                    f"week {num}: marked Complete but does not link to "
                    f"./{deployed[num]}")
        elif complete:
            problems.append(
                f"week {num}: roadmap says Complete but no week-{num}-*/terraform/"
                "main.tf exists")
    return problems


def self_test():
    deployed = {"06": "week-06-billing-export", "07": "week-07-asset-inventory"}
    cases = [
        ("| [06](./week-06-billing-export) | t | s | ✅ Complete |\n"
         "| [07](./week-07-asset-inventory) | t | s | ✅ Complete |\n", 0,
         "both deployed and both marked Complete with links"),
        ("| 06 | t | s | 📅 Planned |\n"
         "| [07](./week-07-asset-inventory) | t | s | ✅ Complete |\n", 1,
         "a deployed week still marked Planned - the 2026-10-24 defect"),
        ("| [06](./week-06-billing-export) | t | s | ✅ Complete |\n"
         "| [07](./week-07-asset-inventory) | t | s | ✅ Complete |\n"
         "| [11](./week-11-pam) | t | s | ✅ Complete |\n", 1,
         "a week claiming Complete with no folder"),
        ("| 06 | t | s | ✅ Complete |\n"
         "| [07](./week-07-asset-inventory) | t | s | ✅ Complete |\n", 1,
         "Complete but no link to the folder"),
    ]
    bad = 0
    for text, want, label in cases:
        got = len(audit(text, deployed))
        ok = got == want
        bad += not ok
        print(f"  [{' ok ' if ok else 'FAIL'}] {label}: {got} problem(s), want {want}")
    if bad:
        print("\nSELF-TEST FAILED: the check cannot detect the defect it exists for.")
        return 1
    print("\nself-test passed: a deployed week marked Planned is caught, a week")
    print("claiming Complete with no folder is caught, and a missing link is caught.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    with open(README, encoding="utf-8") as fh:
        text = fh.read()
    deployed = deployed_weeks()
    problems = audit(text, deployed)

    print(f"{len(deployed)} week folder(s) with terraform/main.tf: "
          f"{', '.join(sorted(deployed))}")
    if problems:
        print(f"\n{len(problems)} roadmap row(s) disagree with the repo:")
        for p in problems:
            print(f"  FAIL {p}")
        print("\nUpdate README.md's Status column. Jay should not be the thing")
        print("that notices this.")
        return 1
    print("Every roadmap row agrees with what is on disk.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

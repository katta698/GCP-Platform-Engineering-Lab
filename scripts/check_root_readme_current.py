#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Every week folder has an accurate row in the root README.

    python scripts/check_root_readme_current.py
    python scripts/check_root_readme_current.py --self-test

For each week-NN-* folder: a roadmap row for week NN must exist, link to that
folder, and not say Planned.

Two traps, both of which the AWS version hit:

  Row formats vary across one file - "| Week 19 |", "| [Week 13](...) |", and
  zero-padded "| [Week 01](...) |". Parse the cell, do not match the line.

  A naive regex for week 1 matches the week 13 row. The week number needs a
  trailing guard so "1" does not swallow "13".
"""
import argparse
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "README.md")

# The trailing (?!\d) is the guard. Without it "1" matches inside "13".
WEEK_CELL = re.compile(r"^\[?(?:Week\s+)?(\d{1,2})(?!\d)\]?(?:\(([^)]*)\))?$")

PLANNED = "Planned"


def parse_rows(text):
    """{week int -> (folder_link, status)} for every roadmap row found."""
    rows = {}
    for line in text.split("\n"):
        s = line.strip()
        if not (s.startswith("|") and s.endswith("|")):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) < 4:
            continue
        m = WEEK_CELL.match(cells[0])
        if not m:
            continue
        rows[int(m.group(1))] = (m.group(2) or "", cells[3])
    return rows


def week_folders(root):
    """{week int -> folder name} for every week-NN-* directory."""
    out = {}
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        m = re.match(r"^week-(\d{1,2})-", name)
        if m and os.path.isdir(os.path.join(root, name)):
            out[int(m.group(1))] = name
    return out


def audit(text, folders):
    """Problems as a list of strings. Pure, so --self-test can drive it."""
    problems = []
    rows = parse_rows(text)
    for num, folder in sorted(folders.items()):
        if num not in rows:
            problems.append(f"week {num}: {folder}/ exists but the README has no row for it")
            continue
        link, status = rows[num]
        if PLANNED in status:
            problems.append(f"week {num}: {folder}/ exists but the row still says {status!r}")
        elif folder not in link:
            problems.append(
                f"week {num}: row does not link to ./{folder} (link is {link!r})")
    return problems


def self_test():
    GOOD = (
        "| Week | Project | Key services | Status |\n"
        "| [Week 01](./week-01-landing) | a | b | OK Complete |\n"
        "| [Week 13](./week-13-hybrid) | c | d | In progress |\n"
        "| Week 14 | planned thing | e | Planned |\n"
    )
    F = {1: "week-01-landing", 13: "week-13-hybrid"}
    cases = [
        ("a correct README", GOOD, F, 0),
        ("week with a folder still marked Planned",
         GOOD.replace("| [Week 13](./week-13-hybrid) | c | d | In progress |",
                      "| Week 13 | c | d | Planned |"), F, 1),
        ("row missing entirely for a built week", GOOD, {**F, 7: "week-07-audit"}, 1),
        ("row present but not linked to the folder",
         GOOD.replace("[Week 01](./week-01-landing)", "Week 01"), F, 1),
        ("row linked to the WRONG folder",
         GOOD.replace("./week-01-landing", "./week-02-other"), F, 1),
        # The trap: week 1's number must not match inside the week 13 row.
        ("week 1 does not match the week 13 row",
         "| Week | P | S | St |\n| [Week 13](./week-13-hybrid) | c | d | Complete |\n",
         {1: "week-01-landing"}, 1),
    ]
    bad = 0
    for name, text, folders, want in cases:
        got = len(audit(text, folders))
        ok = got == want
        print("  %-46s %d problem(s), want %d  %s"
              % (name, got, want, "ok" if ok else "SELF-TEST FAILED"))
        bad += 0 if ok else 1

    # Prove the guard directly: parsing the 13 row must not yield week 1.
    only13 = parse_rows("| [Week 13](./week-13-hybrid) | c | d | Complete |")
    if 1 in only13:
        print("  SELF-TEST FAILED: week 1 parsed out of a week 13 row")
        bad += 1

    print("\nself-test:", "passed" if not bad else "FAILED")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    with open(README, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    folders = week_folders(ROOT)
    problems = audit(text, folders)

    print("%d week folder(s): %s"
          % (len(folders), ", ".join("%02d" % n for n in sorted(folders))))
    if problems:
        print("\n%d problem(s):" % len(problems))
        for p in problems:
            print("  FAIL " + p)
        print("\nThe root README is the first thing a visitor reads. A week that")
        print("exists on disk and says Planned there is the index lying about itself.")
        return 1
    print("Every week folder has an accurate row in the root README.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

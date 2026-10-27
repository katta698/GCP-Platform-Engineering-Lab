#!/usr/bin/env python3
"""Every figure a week DECLARED must end up in the published post, or be retired on purpose.

`check_figures_before_destroy.py` asks whether a declared slot exists on disk.
That is a different question, and passing it is how Week 10 shipped: slot 01 was
captured exactly as planned, committed, and then dropped from the post during a
restructure. The plan called that slot perishable - an empty Groups list cannot
be recaptured once a group exists - so the evidence was taken correctly, stored
correctly, and silently left out of the only place a reader would see it.

This check closes the loop the other way round:

  declared in FIGURE_PLAN.md  ->  referenced by the published post
  captured and committed      ->  referenced by the published post, or retired

A slot may legitimately be dropped. CLAUDE.md is explicit that a picture proving
a resource existed does not earn a figure, because the Terraform run already
proves it. Dropping one is a decision, so it has to be written down: name the
file in docs/UNUSED.txt with a reason. Silence is the defect, not the drop.

Exit 1 on any undeclared drop. Blocking on purpose - a warning nobody reads is
how two slots went missing in the first place.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

LAB = Path(__file__).resolve().parent.parent
BLOG = LAB.parent.parent / "katta698-gcp"

# FIGURE_PLAN.md became a requirement on 2026-09-30, from Week 08 onward. These
# weeks predate it and will never gain one retroactively - a plan written after
# the captures is a description, not a plan. Listed explicitly so the absence is
# a recorded fact rather than a standing failure nobody reads, and so a NEW week
# without a plan still fails.
NO_PLAN_BY_AGE = {
    "week-01-gcp-landing-zone",
    "week-02-keyless-ci",
    "week-03-org-policy-guardrails",
    "week-04-shared-vpc",
    "week-05-project-factory",
    "week-06-billing-export",
    "week-07-asset-inventory",
}

RAW = re.compile(
    r"GCP-Platform-Engineering-Lab/main/(week-[^/]+)/docs/blog/screenshots/([^\"\s]+)"
)
# "| 01 | `01-groups-before.png` | ..." - the file column of a plan's slot table
SLOT = re.compile(r"^\|\s*\d+\s*\|\s*`([^`]+\.png)`", re.MULTILINE)


def referenced_by_posts() -> dict[str, set[str]]:
    """week folder -> {screenshot filenames the published posts point at}"""
    out: dict[str, set[str]] = {}
    if not BLOG.is_dir():
        # The posts live in a separate repository, so this check only works
        # where both are checked out - a workstation, not CI. Skip loudly:
        # a skip reported as a pass is the failure mode this whole check exists
        # to prevent.
        print(f"SKIPPED - the blog repo is not checked out at {BLOG}.")
        print("This check compares declared figures against PUBLISHED posts and")
        print("cannot run without them. It is not a pass. Run it on a workstation.")
        sys.exit(0)
    for post in sorted((BLOG / "posts").glob("week-*.html")):
        text = post.read_text(encoding="utf-8", errors="replace")
        if "GCP Weekly Lab" not in text:
            continue
        for week, filename in RAW.findall(text):
            out.setdefault(week, set()).add(filename)
    return out


def retired(week: Path) -> set[str]:
    unused = week / "docs" / "UNUSED.txt"
    if not unused.is_file():
        return set()
    names = set()
    for line in unused.read_text(encoding="utf-8", errors="replace").splitlines():
        for token in re.findall(r"[\w.\-]+\.png", line):
            names.add(token)
    return names


def main() -> int:
    used = referenced_by_posts()
    problems: list[str] = []
    checked = 0

    for week in sorted(p for p in LAB.glob("week-*") if p.is_dir()):
        shots = week / "docs" / "blog" / "screenshots"
        if not shots.is_dir():
            continue
        checked += 1
        name = week.name
        published = used.get(name, set())
        skip = retired(week)

        if not published:
            print(f"  [ -- ] {name}: no published post references it yet")
            continue

        plan = None
        for candidate in (week / "docs" / "FIGURE_PLAN.md",
                          week / "docs" / "blog" / "FIGURE_PLAN.md"):
            if candidate.is_file():
                plan = candidate
                break

        findings: list[str] = []
        notes: list[str] = []

        if plan is None:
            if name in NO_PLAN_BY_AGE:
                notes.append("predates the FIGURE_PLAN.md rule of 2026-09-30")
            else:
                findings.append(
                    "no FIGURE_PLAN.md - nothing declares what this week owes"
                )
        else:
            declared = set(SLOT.findall(plan.read_text(encoding="utf-8", errors="replace")))
            for slot in sorted(declared - published - skip):
                if "terraform-layout" in slot:
                    # The master standard of 2026-10-25 forbids per-file line
                    # counts, so these slots were replaced by the compact
                    # structure card. Retired by the standard, not dropped.
                    notes.append(f"slot `{slot}` retired by the 2026-10-25 standard")
                    continue
                findings.append(f"slot `{slot}` is DECLARED but the post does not use it")

        on_disk = {p.name for p in shots.glob("*.png")}
        for shot in sorted(on_disk - published - skip):
            findings.append(f"`{shot}` is captured and committed but unreferenced")

        if findings:
            print(f"  [FAIL] {name}")
            for f in findings:
                print(f"           {f}")
            problems.extend(findings)
        else:
            print(f"  [ ok ] {name}: {len(published)} figure(s), nothing dropped silently")
        for n in notes:
            print(f"           note: {n}")

    print()
    if problems:
        print(f"{checked} week(s) checked; {len(problems)} figure(s) dropped without a record.")
        print("Either reference the figure in the post, or retire it in docs/UNUSED.txt")
        print("with a reason. A perishable slot cannot be recaptured after a teardown.")
        return 1

    print(f"{checked} week(s) checked; every declared and captured figure is accounted for.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

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
    # WARN IF THE CHECKOUT IS STALE, because this check reads a sibling
    # working tree and has no idea how old it is. On 2026-11-06 that checkout
    # was over a hundred commits behind origin/main - so the check was
    # confidently comparing declared figures against a months-old copy of the
    # posts, and would have reported either a pass or a failure about content
    # nobody is publishing. A check reading the wrong input is worse than no
    # check, because it is believed.
    try:
        import subprocess
        behind = subprocess.run(
            ["git", "-C", str(BLOG), "rev-list", "--count", "HEAD..origin/main"],
            capture_output=True, text=True, timeout=20).stdout.strip()
        if behind.isdigit() and int(behind) > 0:
            print(f"  WARNING: the blog checkout at {BLOG.name} is {behind} "
                  f"commit(s) behind origin/main.")
            print("  Figures are being compared against posts that may not be "
                  "what is published.")
    except Exception:                                           # noqa: BLE001
        pass

    # Read the posts from origin/main, NOT from the working tree.
    #
    # "Do the PUBLISHED posts reference this figure?" is a question about what
    # is published. A sibling working tree answers a different question, and on
    # 2026-11-06 it answered it with a checkout over a hundred commits behind -
    # blocking a push over two figures the live posts had used for hours.
    # Falling back to the working tree keeps this usable in a fresh clone that
    # has no remote yet.
    post_texts = {}
    try:
        import subprocess
        listing = subprocess.run(
            ["git", "-C", str(BLOG), "ls-tree", "--name-only", "origin/main", "posts/"],
            capture_output=True, text=True, timeout=30)
        names = [n for n in listing.stdout.split() if "/week-" in n and n.endswith(".html")]
        for name in names:
            blob = subprocess.run(["git", "-C", str(BLOG), "show", f"origin/main:{name}"],
                                  capture_output=True, text=True, timeout=30,
                                  encoding="utf-8", errors="replace")
            if blob.returncode == 0:
                post_texts[name.split("/")[-1]] = blob.stdout
    except Exception:                                           # noqa: BLE001
        post_texts = {}

    if post_texts:
        for fname, text in sorted(post_texts.items()):
            for week, filename in RAW.findall(text):
                out.setdefault(week, set()).add(filename)
        return out

    print("  NOTE: could not read posts from origin/main; "
          "falling back to the working tree, which may be stale.")
    for post in sorted((BLOG / "posts").glob("week-*.html")):
        text = post.read_text(encoding="utf-8", errors="replace")
        if "GCP Weekly Lab" not in text:
            continue
        for week, filename in RAW.findall(text):
            out.setdefault(week, set()).add(filename)
    return out


def retired(week: Path) -> tuple[set[str], set[str]]:
    """Return (recorded, pending) slot names from docs/UNUSED.txt.

    RETIRED and PENDING are different claims and the file must not blur
    them. Retired means "this slot will never exist, and here is why".
    Pending means "this slot is outstanding work" - which is the honest
    state for a figure that CANNOT be captured yet, such as a teardown
    result before the teardown, or a cost figure before the charges post.

    Both stop the push being blocked, because both are a RECORD. Only
    pending is reported back, loudly, every run - so an outstanding slot
    cannot quietly become a forgotten one. Silence is the defect this
    check exists for, and a slot filed under the wrong word is a quieter
    version of the same thing.
    """
    unused = week / "docs" / "UNUSED.txt"
    if not unused.is_file():
        return set(), set()
    names, pending = set(), set()
    in_pending = False
    for line in unused.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip().upper()
        if stripped.startswith("PENDING"):
            in_pending = True
        elif stripped.startswith("RETIRED") or stripped.startswith("DROPPED"):
            in_pending = False
        for token in re.findall(r"[\w.\-]+\.png", line):
            names.add(token)
            if in_pending:
                pending.add(token)
    return names, pending


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
        skip, pending = retired(week)

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

        # Pending slots do not block, but they are never silent. A figure
        # that cannot be captured yet is outstanding work; printing it on
        # every run is what stops it becoming a slot nobody remembers.
        for slot in sorted(pending):
            notes.append(f"PENDING, not retired: `{slot}` is still owed")

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

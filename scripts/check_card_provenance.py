#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A terminal card that quotes a command must carry the command's real output.

    python scripts/check_card_provenance.py            # check the lab
    python scripts/check_card_provenance.py --self-test

Committing the `.card` was the fix after an AWS week typeset three figures and
threw the sources away. It preserves what was RENDERED. It does not show the
text ever came from a running command, and on 2026-11-14 Jay asked exactly that
about Week 13's `02-tunnels-up`: the tunnels were genuinely up when the card was
made, nine hours after the deploy and four minutes before teardown, and nothing
in the repo could prove the output was captured rather than typed.

So: every `$ command` block in a card must have its output present verbatim in a
committed capture under `<week>/docs/evidence/`. Redirect the real run there and
render the card from it:

    gcloud compute vpn-tunnels list | tee docs/evidence/02-tunnels-up.txt

A card that is legitimately composed - a layout diagram, a repo tree, annotated
pseudo-output - is declared in `<week>/docs/COMPOSED.txt` with a reason, so the
distinction is recorded instead of assumed.

Weeks 01-13 are grandfathered: they predate the rule and retrofitting evidence
after teardown would mean inventing it, which is the defect, not the fix.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Explicit, not a date comparison: a reader should see exactly what is exempt.
GRANDFATHERED = {f"{n:02d}" for n in range(1, 14)}

PROMPT = re.compile(r"^\s*\$ (.+)$")


def blocks(card_text):
    """[(command, [output lines]), ...] from a card body.

    Comment lines are the card's own annotation, not output, so they are not
    evidence and are not required to appear in the capture.
    """
    body = card_text.split("\n---\n", 1)[-1]
    out, cmd, buf = [], None, []
    for line in body.split("\n"):
        m = PROMPT.match(line)
        if m:
            if cmd is not None:
                out.append((cmd, buf))
            cmd, buf = m.group(1).strip(), []
        elif cmd is not None:
            s = line.strip()
            if s and not s.startswith("#"):
                buf.append(s)
    if cmd is not None:
        out.append((cmd, buf))
    return out


def composed(week_dir):
    p = os.path.join(week_dir, "docs", "COMPOSED.txt")
    if not os.path.exists(p):
        return set()
    text = open(p, encoding="utf-8").read()
    return set(re.findall(r"([\w.-]+\.card)", text))


def evidence(week_dir):
    d = os.path.join(week_dir, "docs", "evidence")
    if not os.path.isdir(d):
        return ""
    chunks = []
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            try:
                chunks.append(open(p, encoding="utf-8", errors="replace").read())
            except OSError:
                pass
    return "\n".join(chunks)


def check_week(week_dir, week_num):
    """[] when the week is clean, else a list of failure strings."""
    cards = []
    for base, _dirs, files in os.walk(os.path.join(week_dir, "docs")):
        if ".terraform" in base:
            continue
        cards += [os.path.join(base, f) for f in files if f.endswith(".card")]
    if not cards:
        return []

    skip = composed(week_dir)
    raw = evidence(week_dir)
    fails = []
    for card in sorted(cards):
        name = os.path.basename(card)
        if name in skip:
            continue
        text = open(card, encoding="utf-8", errors="replace").read()
        bs = [b for b in blocks(text) if b[1]]
        if not bs:
            continue                      # no quoted output: nothing to source
        if not raw:
            fails.append(f"{week_num}/{name}: quotes command output, but "
                         f"docs/evidence/ holds nothing and it is not in "
                         f"docs/COMPOSED.txt")
            continue
        for cmd, lines in bs:
            missing = [l for l in lines if l not in raw]
            if missing:
                fails.append(f"{week_num}/{name}: output of `{cmd}` is not in "
                             f"docs/evidence/ ({len(missing)} line(s), first: "
                             f"{missing[0][:60]!r})")
    return fails


def run(root=ROOT, quiet=False):
    weeks = sorted(d for d in os.listdir(root)
                   if re.match(r"^week-\d{2}-", d)
                   and os.path.isdir(os.path.join(root, d)))
    fails, checked, exempt = [], 0, []
    for w in weeks:
        num = w[5:7]
        if num in GRANDFATHERED:
            exempt.append(num)
            continue
        checked += 1
        fails += check_week(os.path.join(root, w), num)

    if not quiet:
        if exempt:
            print(f"  grandfathered (predate the rule): {', '.join(exempt)}")
        print(f"  {checked} week(s) in scope")
        for f in fails:
            print(f"  FAIL  {f}")
        print("  Every quoted command output is backed by a committed capture."
              if not fails else f"  {len(fails)} card(s) without provenance.")
    return 1 if fails else 0


# ---------------------------------------------------------------------------

def self_test():
    import shutil
    import tempfile

    tmp = tempfile.mkdtemp()
    try:
        def week(num, card_body, raw=None, composed_txt=None):
            d = os.path.join(tmp, f"week-{num}-x")
            os.makedirs(os.path.join(d, "docs", "blog"), exist_ok=True)
            with open(os.path.join(d, "docs", "blog", "01-a.card"), "w",
                      encoding="utf-8") as fh:
                fh.write("title: t\n---\n" + card_body)
            if raw is not None:
                os.makedirs(os.path.join(d, "docs", "evidence"), exist_ok=True)
                with open(os.path.join(d, "docs", "evidence", "01-a.txt"), "w",
                          encoding="utf-8") as fh:
                    fh.write(raw)
            if composed_txt is not None:
                with open(os.path.join(d, "docs", "COMPOSED.txt"), "w",
                          encoding="utf-8") as fh:
                    fh.write(composed_txt)
            return d

        CARD = "$ gcloud thing list\nNAME   STATUS\na      UP\n"
        cases = []

        # 1. output present in the capture -> pass
        week("20", CARD, raw="NAME   STATUS\na      UP\n")
        cases.append(("output backed by a capture", run(tmp, quiet=True), 0))
        shutil.rmtree(os.path.join(tmp, "week-20-x"))

        # 2. no evidence directory at all -> fail
        week("21", CARD)
        cases.append(("no capture committed", run(tmp, quiet=True), 1))
        shutil.rmtree(os.path.join(tmp, "week-21-x"))

        # 3. capture exists but does not contain the quoted line -> fail.
        #    This is the case committing the .card alone would pass.
        week("22", CARD, raw="NAME   STATUS\nb      DOWN\n")
        cases.append(("capture contradicts the card", run(tmp, quiet=True), 1))
        shutil.rmtree(os.path.join(tmp, "week-22-x"))

        # 4. declared composed -> pass
        week("23", CARD, composed_txt="01-a.card - a layout sketch, not a run\n")
        cases.append(("declared in COMPOSED.txt", run(tmp, quiet=True), 0))
        shutil.rmtree(os.path.join(tmp, "week-23-x"))

        # 5. a card with no $ prompt quotes nothing -> pass
        week("24", "just a tree\n  src/\n")
        cases.append(("card quotes no command", run(tmp, quiet=True), 0))
        shutil.rmtree(os.path.join(tmp, "week-24-x"))

        # 6. a grandfathered week is not examined even when it would fail
        week("13", CARD)
        cases.append(("grandfathered week skipped", run(tmp, quiet=True), 0))
        shutil.rmtree(os.path.join(tmp, "week-13-x"))

        # 7. comment lines are annotation, not output, so they need no capture
        week("25", "$ gcloud thing list\nNAME\na\n# this is a note\n",
             raw="NAME\na\n")
        cases.append(("comments are not evidence", run(tmp, quiet=True), 0))
        shutil.rmtree(os.path.join(tmp, "week-25-x"))

        bad = 0
        for label, got, want in cases:
            ok = got == want
            bad += not ok
            print(f"  {'ok  ' if ok else 'FAIL'}  {label} "
                  f"(exit {got}, expected {want})")
        print("  self-test passed" if not bad else f"  {bad} case(s) failed")
        return 1 if bad else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    sys.exit(self_test() if a.self_test else run())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Watch a Secret Manager rotation notification arrive, and measure what it changed.

    python scripts/measure-rotation.py --until 2026-11-04T21:05:00Z

The claim under test
--------------------
Google's documentation says that at `next_rotation_time`, Secret Manager
"triggers a SECRET_ROTATE message to the designated Pub/Sub topics", and that
"you must configure a Pub/Sub subscriber to receive and act on" it.

Read plainly, that means the schedule changes nothing about the secret. This
script is what turns that reading into evidence rather than a paraphrase, by
recording three things across the notification:

  1. the version count and the primary version's name, before
  2. the notification itself, pulled off the observer subscription
  3. the version count and primary version's name, after

If the count and the name are identical either side of a message that says
SECRET_ROTATE, the schedule rotated nothing. If they differ, the claim is wrong
and the post should say so instead.

Why it polls rather than subscribing properly
---------------------------------------------
A streaming pull would be the right shape for a real subscriber. Here the point
is to NOT act on the message - the observer subscription exists so a
notification can be read back and left alone. A pull with
`--auto-ack=false`-equivalent semantics keeps the message retrievable for the
24h retention window, so the figure can be captured after the fact.

Lesson carried from Week 11
---------------------------
`run()` returns stdout and stderr SEPARATELY. The Week 11 version concatenated
them and gcloud's progress chatter on stderr broke every json.loads, which cost
25 minutes of a 30-minute measurement window. gcloud writes diagnostics to
stderr even on success; never parse the two together.
"""
import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# subprocess cannot launch a bare `gcloud` on Windows: it is a .CMD shim and
# CreateProcess does not apply PATHEXT. Same fix as Week 03's lag script.
GCLOUD = shutil.which("gcloud")
if not GCLOUD:
    sys.exit("gcloud not on PATH")


def run(args):
    """Return (returncode, stdout, stderr). Never merged - see the module docstring."""
    p = subprocess.run(
        [GCLOUD, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return p.returncode, p.stdout, p.stderr


def jrun(args):
    """Run with --format=json and parse stdout only."""
    rc, out, err = run([*args, "--format=json"])
    if rc != 0:
        raise RuntimeError(f"gcloud {' '.join(args)} failed rc={rc}\n{err.strip()}")
    try:
        return json.loads(out)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"gcloud {' '.join(args)} returned non-JSON stdout:\n{out[:400]}") from exc


def now():
    return datetime.now(timezone.utc)


def stamp():
    return now().strftime("%H:%M:%S")


def secret_state(secret, project):
    """Version count and primary version - the two things a rotation would move."""
    versions = jrun([
        "secrets", "versions", "list", secret,
        f"--project={project}",
    ])
    enabled = [v for v in versions if v.get("state") == "ENABLED"]
    # Secret Manager has no "primary" pointer the way KMS does; the newest
    # ENABLED version is what `versions access latest` resolves to, so that is
    # the thing a consumer would actually read.
    latest = max((v["name"] for v in enabled), default=None)
    return {
        "total": len(versions),
        "enabled": len(enabled),
        "latest_enabled": latest,
    }


def pull_notifications(subscription, project, limit=10):
    """Pull without acking, so the message stays retrievable for the figure.

    Note on what the observed lag can and cannot mean. gcloud's `pull` does not
    ack by default, but a pulled message is then invisible for the
    subscription's ack deadline (60s here). So any poll that returns a message
    hides the subscription for the next minute, and the arrival time this
    script records is bounded below by the poll interval and above by the ack
    deadline.

    The DELIVERY LAG is therefore not a precise measurement and must not be
    published as one - the same error Week 03's enforcement-lag script made and
    Week 11 corrected by publishing a range. What this script measures
    precisely is whether the secret changed, which is the week's actual claim.
    """
    rc, out, err = run([
        "pubsub", "subscriptions", "pull", subscription,
        f"--project={project}",
        f"--limit={limit}",
        "--format=json",
    ])
    if rc != 0:
        # An empty subscription is not an error; a genuine failure is.
        raise RuntimeError(f"pull failed rc={rc}\n{err.strip()}")
    try:
        msgs = json.loads(out) if out.strip() else []
    except json.JSONDecodeError:
        raise RuntimeError(f"pull returned non-JSON stdout:\n{out[:400]}")

    found = []
    for m in msgs:
        msg = m.get("message", {})
        attrs = msg.get("attributes", {}) or {}
        found.append({
            "eventType": attrs.get("eventType"),
            "secretId": attrs.get("secretId"),
            "publishTime": msg.get("publishTime"),
            "data": msg.get("data"),
            "attributes": attrs,
        })
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="katta698-gcp-security")
    ap.add_argument("--secret", default="wk12-app-db-password")
    ap.add_argument("--subscription", default="wk12-rotation-observer")
    ap.add_argument("--until", required=True,
                    help="RFC3339 next_rotation_time to watch for, e.g. 2026-11-04T21:05:00Z")
    ap.add_argument("--poll", type=int, default=10, help="seconds between polls")
    ap.add_argument("--grace", type=int, default=600,
                    help="seconds to keep watching after --until before giving up")
    ap.add_argument("--json", help="write the measurement to this path")
    args = ap.parse_args()

    due = datetime.strptime(args.until, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

    before = secret_state(args.secret, args.project)
    print(f"[{stamp()}] before:  {before['total']} versions, "
          f"{before['enabled']} enabled, latest={before['latest_enabled']}")
    print(f"[{stamp()}] notification due at {args.until}; "
          f"{(due - now()).total_seconds():.0f}s from now")

    # Drain anything already sitting on the subscription so a message from an
    # EARLIER notification cannot be mistaken for this one. Without this the
    # second measurement of the session reads the first one's message and
    # reports an instant arrival.
    stale = pull_notifications(args.subscription, args.project)
    if stale:
        print(f"[{stamp()}] note: {len(stale)} message(s) already on the subscription "
              f"before this window; they are excluded by publishTime")

    deadline = due.timestamp() + args.grace
    arrival = None
    message = None

    while time.time() < deadline:
        msgs = pull_notifications(args.subscription, args.project)
        fresh = [
            m for m in msgs
            if m["eventType"] == "SECRET_ROTATE"
            and m["publishTime"]
            and datetime.strptime(m["publishTime"][:19], "%Y-%m-%dT%H:%M:%S")
                .replace(tzinfo=timezone.utc) >= due
        ]
        if fresh:
            arrival = now()
            message = fresh[0]
            lag = (arrival - due).total_seconds()
            print(f"[{stamp()}] SECRET_ROTATE received. published={message['publishTime']}, "
                  f"observed {lag:+.0f}s against the scheduled time")
            break
        time.sleep(args.poll)

    if not message:
        print(f"[{stamp()}] no SECRET_ROTATE arrived within {args.grace}s of {args.until}")
        print("  This is a FAILED measurement, not a finding. Do not write it up as one.")
        return 1

    # Give Secret Manager room to do something, if it were going to. It is not,
    # but a measurement taken in the same second as the notification could not
    # tell the difference between "nothing happened" and "not yet".
    print(f"[{stamp()}] waiting 60s before re-reading, so 'unchanged' cannot mean 'too early'")
    time.sleep(60)

    after = secret_state(args.secret, args.project)
    print(f"[{stamp()}] after:   {after['total']} versions, "
          f"{after['enabled']} enabled, latest={after['latest_enabled']}")

    unchanged = (before["total"] == after["total"]
                 and before["latest_enabled"] == after["latest_enabled"])

    print()
    if unchanged:
        print("RESULT: notification delivered, secret UNCHANGED.")
        print("  The rotation schedule published a message and did nothing else.")
    else:
        print("RESULT: the secret CHANGED across the notification.")
        print("  Something is acting on the topic. If the rotator is deployed this is")
        print("  the expected outcome; if it is not, the week's premise is wrong and")
        print("  the post must say so.")

    record = {
        "measured_at": now().isoformat(),
        "secret": args.secret,
        "scheduled_rotation_time": args.until,
        "notification": message,
        "observed_at": arrival.isoformat(),
        "observed_lag_seconds": round((arrival - due).total_seconds()),
        "before": before,
        "after": after,
        "secret_unchanged": unchanged,
    }
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2)
        print(f"\nwritten to {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

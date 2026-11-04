# -*- coding: utf-8 -*-
"""The rotator Secret Manager does not ship.

This is the whole of what a `SECRET_ROTATE` notification requires somebody to
write. Thirty lines of it, which is both the point and the problem: the work is
small enough that its absence looks like an oversight rather than a design, and
a rotation schedule configured without it silently does nothing forever.

What a real rotator does that this one does not
----------------------------------------------
This adds a new version and disables the previous one. A production rotator for
a database password has to do three more things, and all three are the hard
part:

  1. change the credential at the system that owns it (the database), not just
     in Secret Manager - otherwise the new version is a password that opens
     nothing
  2. overlap the old and new credentials so in-flight consumers are not cut off
     mid-request, which is why disabling the old version immediately is wrong
     for anything real
  3. be idempotent, because Secret Manager retries a notification for up to
     seven days and "in-flight rotations must complete before another rotation
     can be started"

Named rather than skipped, because the gap between "adds a version" and
"rotates a credential" is where the actual engineering lives, and a lab that
implied otherwise would be teaching the easy half as if it were the whole.

Why it keys on the event type
-----------------------------
The topic carries more than rotation. Secret Manager publishes
`SECRET_VERSION_ADD` too - which this function itself causes - so a rotator that
acts on every message rotates in an infinite loop, each version triggering the
next. Filtering on `SECRET_ROTATE` is not defensive coding; it is the difference
between a rotator and a runaway.
"""
import base64
import json
import os
import secrets
import string

import functions_framework
from google.cloud import secretmanager

PROJECT = os.environ["SECRET_PROJECT"]
SECRET = os.environ["SECRET_ID"]

# Matches the alphabet Terraform's random_password uses for the initial value,
# so a rotated secret is indistinguishable in shape from the original.
ALPHABET = string.ascii_letters + string.digits + "!#$%&*+-=?@^_"


def new_password(length: int = 32) -> str:
    # secrets, not random. The latter is seeded predictably and is the wrong
    # module for anything that protects something.
    return "".join(secrets.choice(ALPHABET) for _ in range(length))


@functions_framework.cloud_event
def rotate(cloud_event):
    attrs = (cloud_event.data or {}).get("message", {}).get("attributes", {}) or {}
    event_type = attrs.get("eventType")
    secret_name = attrs.get("secretId", "")

    print(json.dumps({
        "received": event_type,
        "secretId": secret_name,
        "attributes": attrs,
    }))

    if event_type != "SECRET_ROTATE":
        # Not an error. Acknowledge and stop, so the message is not redelivered.
        print(f"ignoring {event_type!r}: only SECRET_ROTATE triggers a rotation")
        return

    # Act only on the secret this function was deployed for. The topic is a
    # project-level resource and any secret in the project could be pointed at
    # it; a rotator that trusts the attribute rotates somebody else's secret.
    expected = f"projects/{PROJECT}/secrets/{SECRET}"
    if secret_name and not secret_name.startswith("projects/"):
        print(f"unexpected secretId shape {secret_name!r}; refusing to act")
        return
    if secret_name and secret_name.split("/secrets/")[-1] != SECRET:
        print(f"notification is for {secret_name!r}, not {expected!r}; ignoring")
        return

    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{PROJECT}/secrets/{SECRET}"

    # Record what the newest enabled version was, so the log shows the move
    # rather than just the arrival.
    before = [
        v.name for v in client.list_secret_versions(request={"parent": parent})
        if v.state == secretmanager.SecretVersion.State.ENABLED
    ]

    added = client.add_secret_version(request={
        "parent": parent,
        "payload": {"data": new_password().encode("utf-8")},
    })
    print(f"added {added.name}")

    # Disable the versions that were current before this rotation. Deliberately
    # DISABLE and not DESTROY: a disabled version can be re-enabled if the
    # rotation turns out to have broken a consumer, and a destroyed one cannot.
    #
    # In production this step belongs behind an overlap window, not here. See
    # the module docstring.
    for name in before:
        client.disable_secret_version(request={"name": name})
        print(f"disabled {name}")

    print(json.dumps({
        "rotated": True,
        "new_version": added.name,
        "disabled": before,
    }))

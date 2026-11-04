# Week 12 — Secret management: CMEK, and the two things called "rotation"

**Status:** 🔨 In progress — built and validated locally, not yet deployed.

A secret encrypted with a key we hold, carrying a rotation schedule — and the
measurement that shows the schedule rotates nothing until somebody writes the
rotator.

## Cost note

| | |
| --- | --- |
| Runs continuously | one Cloud KMS software symmetric key version |
| Teardown removes | the secret, the topic, the subscription, the rotator — and **not** the key, see below |
| Rough monthly figure if left up | **$0.06** for the key version, plus $0 for everything else while the free tiers hold |

**This is the first week in this lab whose main resource has no free tier at
all.** Not because it is expensive — six cents a month is not expensive — but
because every prior week's `$0` was a free-tier `$0`, and this one bills from
the first hour. Prices read from this lab's own pricing export, built in
Week 06, not from a rate card:

| SKU | Free tier | Then |
| --- | --- | --- |
| Active software symmetric key versions | **none** | $0.06 / month |
| Secret version replica storage | first 6 replica-months | $0.06 / month |
| Secret access operations | first 10,000 | $0.03 |
| Secret rotate operations | first 3 | $0.05 each |

So the secret, its replicas and the handful of rotation notifications this week
generates all land inside a free tier, and the key version does not.

**The teardown does not stop the key charge, and that is a finding rather than
an oversight.** Google counts a key version as active — and billable — if it is
*Enabled, Disabled, or Scheduled for destruction*. Only `DESTROYED` stops it.
A destroyed version first spends `destroyScheduledDuration` in
`DESTROY_SCHEDULED`, which defaults to **30 days**; this week sets it to 24h
precisely so the week does not meter for a month after its cleanup reports
success. Disabling a key stops it working and does not stop it charging.

Actual measured cost will be published once the charges post. Nothing here is
quoted as an observation until then.

## What this proves

Two things, and both are denials.

**1. A Secret Manager rotation schedule does not rotate a secret.** It publishes
a `SECRET_ROTATE` message to a Pub/Sub topic and stops. Google documents it
plainly — *"You must configure a Pub/Sub subscriber to receive and act on"* the
notification — and the console still presents it under the word "rotation" next
to a period you choose. Configure it and walk away and every consumer reads the
same credential forever.

The evidence is a notification that demonstrably arrived sitting beside a
version count that demonstrably did not move, and then the same schedule firing
again with a rotator subscribed and the count moving. Either half alone proves
nothing.

**2. Under CMEK, the key holder is a kill switch.** Disabling the key version —
touching neither the secret nor a single IAM binding — makes the value
unreadable to a caller that still holds every permission needed to read it.
Attempted as an identity that genuinely holds `secretmanager.versions.access`,
because an under-privileged attempt fails identically and proves nothing.

**And a third, about the tooling rather than the cloud.** Google's
documentation now says key rings and keys can be deleted. The Terraform
provider's own documentation for `google_kms_crypto_key` still says
*"CryptoKeys cannot be deleted from Google Cloud Platform ... will not delete
the resource from the project."* Both cannot be right.
`scripts/teardown-kms.sh` runs the documented deletion chain to find out which,
because that is the only way to know.

## The contrast the week is built on

Both of these are in the same file, forty lines apart, and Google calls both of
them rotation:

| | Cloud KMS `rotation_period` | Secret Manager `rotation_period` |
| --- | --- | --- |
| Minimum | greater than 1 day | 1 hour |
| What happens when it elapses | a new `CryptoKeyVersion` is generated and made primary | a Pub/Sub message is published |
| New material created | yes | **no** |
| Code you must write | none | **all of it** |
| Works if you ignore it | yes | no |

## What exists

Stage 1 — ten resources in the platform **security** project from Week 01,
whose `cloudkms` and `secretmanager` enablements this week is the first to use:

```
katta698-gcp-security
├── pubsub.googleapis.com                      enabled by this week
├── Secret Manager service agent               created explicitly, before the secret
├── wk12-secrets                               key ring, global
│   └── wk12-app-db-password                   SOFTWARE symmetric, 90d KMS rotation,
│       │                                      destroy_scheduled_duration 24h
│       └── IAM: service agent -> cryptoKeyEncrypterDecrypter
├── wk12-secret-rotation-events                topic (MANDATORY, not optional)
│   ├── IAM: service agent -> pubsub.publisher
│   └── wk12-rotation-observer                 pull subscription, nothing attached
└── wk12-app-db-password                       secret, automatic replication + CMEK
    ├── topics  = [wk12-secret-rotation-events]
    ├── rotation = 1h (Google's minimum)
    └── version 1                              value generated, never written to a file
```

Stage 2 adds the rotator: a Cloud Functions gen2 function on the topic, its own
service account holding `secretVersionAdder` and `secretVersionManager` on that
one secret — and deliberately **not** `secretAccessor`. A rotator does not need
to read the secret it rotates; it writes a new value and never needs the old
one.

The staging is the experiment, not a convenience. The central measurement needs
one notification to fire with nothing subscribed.

## Order of work

1. Amend Week 02 with project-scoped grants on the security project, and apply
   it by hand — Week 02 is the human-run layer that defines who CI is.
2. Create the `gcp-week-12` HCP workspace through the API, not `terraform init`.
3. `scripts/set-next-rotation.sh 8`, then apply stage 1.
4. `scripts/validate.sh` — reads the cloud, not Terraform state.
5. `scripts/measure-rotation.py --until <the time just set>` — **the load-bearing
   measurement**, and it must be taken before anything subscribes to the topic.
6. `scripts/cmek-killswitch.sh` — the second denial.
7. Re-run `set-next-rotation.sh`, apply with `deploy_rotator = true`, measure
   again. The count should move this time.
8. `scripts/teardown-kms.sh --stage report`, then `terraform destroy`, then
   `--stage report` again to see what survived it.

Step 5 before step 7 is not interchangeable. Once the rotator exists there is no
route back to an unrotated observation without rebuilding the week.

## Measured findings

Pending deployment. Nothing is recorded here until it has been run.

## Files

| Path | What it is |
| --- | --- |
| `terraform/main.tf` | stage 1 — key, secret, topic, subscription |
| `terraform/rotator.tf` | stage 2 — the function, gated on `deploy_rotator` |
| `rotator/main.py` | the rotator Secret Manager does not ship |
| `scripts/set-next-rotation.sh` | moves the next notification without changing the period |
| `scripts/measure-rotation.py` | the central measurement |
| `scripts/cmek-killswitch.sh` | the CMEK denial, reversible, restores in a trap |
| `scripts/teardown-kms.sh` | the key-ring deletion experiment, staged |
| `scripts/validate.sh` | every assertion against the cloud |
| `docs/FIGURE_PLAN.md` | seven slots, declared before capture |
| `LAB.md` | the runbook — prerequisites, commands, expected output, troubleshooting |

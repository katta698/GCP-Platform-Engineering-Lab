# Week 06 — Billing export and budget alerts

Status: ✅ **Complete 2026-09-27.** Deployed 2026-09-26; pricing export linked
2026-09-27 once the billing-account grant was made.

## Cost note

**$0 for what this week adds**, and for the first time that is a measured claim
rather than an asserted one:

```
2294 rows · 4 projects · 2026-07-01 → 2026-09-26 · $0.006 total
```

BigQuery storage for the billing export is the only ongoing charge, and at this
volume it is far below the 10 GiB free tier. The budget, the topic and the org
policy override cost nothing.

**This week is exempt from teardown.** `scripts/cleanup.sh` does not destroy the
export or the budget, and that is deliberate: a cost-observability layer that is
removed at the end of the week observes nothing. Weeks 07+ depend on it existing.
Unlinking an export is console-only in any case, so a script cannot fully undo it.

## What this week actually found

The plan was "the lab has no queryable record of its own spend, so build one".
That was wrong, and the wrongness is the week.

**A detailed usage cost export was already running** — into a dataset in the seed
project, since 2026-07-01, unqueried. The five previous weeks' `$0` claims had
been provable for three months and nobody had asked. The gap was never missing
infrastructure. It was that no one pointed a query at the infrastructure already
there.

So the week's real work split in two: find out what was already true, and build
only the part that genuinely was not there.

## What is NOT here, and cannot be

Enabling a Cloud Billing export to BigQuery is **console-only**. There is no
gcloud command, no Terraform resource, and no public REST endpoint —
`/v1/billingAccounts/{id}/exportSettings` returns 404. Confirmed against the
provider schema (nine `google_billing_*` resources, no export among them) and
against Google's own `terraform-google-billing-dashboard` module, which creates
datasets and then tells the operator to link them by hand.

The configuration therefore builds the destination and the alerting path, and
the link itself is made once, in the console. That is not a shortcut; it is the
only path Google offers.

## The week's result: an opaque error with a specific cause

Attaching the Pub/Sub topic to the budget failed with:

```
Error 400: Precondition check failed.
```

No resource, no permission, no policy named. The full REST response carried no
`details` array either — that message is all there is.

The cause is **Week 03's own guardrail**. Attaching a topic to a budget is not a
reference: Cloud Billing writes its own Google-owned service agent onto the
topic's IAM policy as a publisher. `iam.allowedPolicyMemberDomains` was enforced
org-wide and restricted to this Workspace customer ID, so that principal was
outside the allowed set, the IAM write was refused, and the refusal surfaced as
a precondition.

Four measurements pinned it before anything was changed:

| probe | result | rules out |
| --- | --- | --- |
| bogus topic name | `NOT_FOUND` | the API does resolve the topic |
| real topic, budget A | `FAILED_PRECONDITION` | |
| real topic, budget B | `FAILED_PRECONDITION` | the budget object |
| `testIamPermissions` on the topic | `setIamPolicy` **held** | the caller |

Identical as `tf-apply` and as a human org admin. A cause surviving all four is
org-level, not resource-level.

**The console says so and the API does not.** The budget's own notification
section carries the sentence "It may not be possible to add a Pub/Sub topic if it
belongs to an organization that has domain restricted sharing enabled" — visible
in `02-budget-pubsub-attached.png`. The same condition, reached through the API,
produces four words that name none of it.

### The fix is scope, not surrender

The override applies to **one project**, the one holding the topic. Every other
project in the organization keeps Week 03's restriction unchanged. It lives in
`main.tf` next to the reason it exists, rather than being a console click nobody
can later explain.

```
organization                    iam.allowedPolicyMemberDomains = <customer ID>
└── katta698-gcp-logging        override: allow all   ← this week, and only here
```

### And the identity, measured rather than guessed

The first draft granted `roles/pubsub.publisher` to
`billing-budgets@system.gserviceaccount.com`, guessed from the shape other Google
service agents take. It does not exist. The real one, read off the topic's IAM
policy after the attach succeeded:

```
roles/pubsub.publisher
  serviceAccount:billing-budget-alert@system.gserviceaccount.com
```

Singular `budget`, and `alert` rather than `budgets`. Close enough to the guess
to survive review, wrong enough to fail. The address is published in no
documentation consulted — the only reliable way to learn it is to let Google
write it and then read it back.

## Measured findings

**A detailed export is a strict superset of a standard export.** Google's table
reference: it "includes all of the data fields from the standard usage cost
table, along with additional fields that provide resource-level cost data". The
standard dataset this week originally created was deleted before it ever
received a row — running both stores a subset twice and bills for it twice.

**Re-pointing an export does not move its history.** The detailed export was left
in the seed project rather than consolidated into the logging project, because
the old table stops receiving rows and the new dataset backfills at most the
previous month. Tidiness would have cost July and August.

**A multi-region dataset backfills; a single-region one does not.** Multi-region
recovers the previous month on first enablement. Location is immutable after
creation, so the only correction is a new dataset and a re-link.

**Organization policy changes are not instant in either direction.** Week 03
measured the lag on enforcement; the same lag applies to relaxation. The budget
attach races it, so `time_sleep` sits between the override and the budget. Without
it the apply fails with the same unnamed precondition the week started with.

**The constraint's own description is incomplete on this point.** It states you do
not need to add the `google.com` customer ID "in order to interoperate with Google
services" — yet this Google service was blocked until the constraint was overridden
for the project.

## Order of work

1. Read the live export state first — it may already exist, and here it did
2. `terraform apply` — remote, as `tf-apply`
3. `./scripts/validate.sh`
4. Link the remaining export in the console

No grants were needed in `week-02-keyless-ci` this week, the first time in four
weeks. `tf-apply` already held `roles/orgpolicy.policyAdmin` from Week 03, which
turned out to be exactly what the override required.

## The permission split that blocked the pricing export

Configuring any export requires **both** `billing.accounts.getPricing` and
`billing.accounts.updateUsageExportSpec`, and those two live in different roles:

| role | `getPricing` | `updateUsageExportSpec` |
| --- | --- | --- |
| `roles/billing.viewer` | ✅ | |
| `roles/billing.admin` | ✅ | ✅ |
| `roles/billing.user` | | ✅ |
| `roles/billing.costsManager` | | ✅ |

The operating account held `user` and `costsManager` — both halves of the second
permission and neither of the first — so the console showed the export page
normally and refused only at the point of configuring it. `roles/billing.viewer`
is the narrowest role that closes the gap.

Granting it needs `billing.accounts.setIamPolicy`, which sits only in
`roles/billing.admin`, held by the personal account that created the billing
account. Billing-account bindings are never Terraform-managed here, so this is
an out-of-band grant — but not a console one. gcloud holds both identities at
once, so `scripts/grant-billing-role.sh` does it with `--account`.

**`gcloud billing accounts add-iam-policy-binding` cannot make this grant.** It
reads the policy and sends it back verbatim, including the `"auditConfigs": []`
that `getIamPolicy` returns, and the API rejects the empty array:

```
ERROR: (gcloud.billing.accounts.add-iam-policy-binding) INVALID_ARGUMENT:
Request contains an invalid argument.
```

naming no argument. Sending only `version`, `bindings` and `etag` succeeds, so
the script does the modify-write itself.

## Outstanding

**Nothing blocking.** The pricing export is linked to
`katta698-gcp-logging.billing_pricing` and its dataset is empty only because
pricing data is not backfilled — it starts at enablement and takes up to 48
hours to first appear. `validate.sh` distinguishes that case from a permissions
failure rather than reporting both and leaving the reader to guess.

## Evidence

- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/blog/shotlist.md` — what each shot proves, and what has no shot
- `docs/references.md` — what each source settled, and what none of them did

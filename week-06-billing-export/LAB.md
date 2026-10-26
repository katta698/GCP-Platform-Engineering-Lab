# Lab Guide — Week 06: Billing Export and Budget Alerting

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-06-billing-export/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-09-26. **Deliberately still running** —
see §6.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Billing account | with `roles/billing.admin` available to someone — see the note below |
| Apply identity | `roles/orgpolicy.policyAdmin` at the organization (for the scoped exception), `roles/bigquery.admin` and `roles/pubsub.admin` on the target project |
| Operator | `roles/billing.costsManager` to manage budgets; `roles/billing.viewer` to configure an export |
| APIs | `billingbudgets`, `cloudbilling`, `bigquery`, `pubsub`, `orgpolicy` on the quota project |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

### The permission split that will stop you

**`billing.accounts.getPricing` is in `billing.viewer` and `billing.admin`
only** — not in `billing.user` or `billing.costsManager`. The console needs it
*and* `updateUsageExportSpec` together to configure any export.

And on this account, **`gcloud billing accounts add-iam-policy-binding` is
unusable**: it echoes back `auditConfigs: []` and fails with `INVALID_ARGUMENT`
naming no argument. `scripts/grant-billing-role.sh` does the read-modify-write
over REST instead.

**Cross-week:** Week 03's `iam.allowedPolicyMemberDomains` constraint blocks the
budget's notification path — §3 is about working around it correctly.

---

## 2. Check what already exists, before writing anything

```bash
bq ls --project_id=<PROJECT> && \
gcloud billing accounts describe <BILLING_ACCOUNT>
```

**Actual result 2026-09-26:** a detailed usage cost export had been running into
the seed project since **2026-07-01**, unqueried — 2,294 rows, 4 projects,
**$0.006 total**. The week's written premise ("the lab has no queryable cost
source") was false before it was written.

**Read live state before believing a week's own premise, not just its config.**

---

## 3. Deploy

```bash
cd week-06-billing-export/terraform
terraform init
terraform plan      # expect: 7 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`

| Resource | Purpose |
| --- | --- |
| `google_bigquery_dataset` | pricing export destination |
| `google_pubsub_topic` | budget notification channel |
| `google_org_policy_policy` | **project-scoped exception** to Week 03's domain restricted sharing |
| `time_sleep` | 120s, so the exception propagates before the budget is written |
| `google_billing_budget` | with `all_updates_rule` pointing at the topic |
| 2 × `google_project_service` | API enablement |

### Why the exception and the sleep exist

Attaching a Pub/Sub topic to a budget makes Cloud Billing write **its own
Google-owned service agent** onto the topic as publisher. Week 03's
`iam.allowedPolicyMemberDomains` constraint blocks that, and the API's entire
response is:

```
Error 400: Precondition check failed
```

No resource, no policy, no `details` array. The **console** states the real cause
in full on the budget's own notification section; the API does not.

The fix is a **project-scoped** override of the constraint — not an
organization-wide relaxation — plus a wait, because org policy changes take
75–108 seconds to take effect in either direction (measured in Week 03).

---

## 4. Configure the export (console only)

The export link itself **cannot be automated**. Terraform has no resource for
it, and Playwright could not drive the form: it sets project and dataset
correctly and the button transitions, but no save request is ever issued.

**Treat this form as human-only.** Billing → Billing export → BigQuery export →
Edit settings → choose project and dataset → Save.

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-09-26 |
| --- | --- | --- |
| The pre-existing export is present and has rows | rows > 0 | 2,294 rows, 4 projects |
| It answers the cost question | a per-project total | **$0.006** since 2026-07-01 |
| Pricing dataset exists | resolves in the logging project | present |
| Budget has a notification path | `all_updates_rule` set | set, topic attached |
| Who Google publishes as | reported, not guessed | `billing-budget-alert@system.gserviceaccount.com` |
| Exception blast radius | one project only | project-scoped, org untouched |

**Read the publisher identity back; never write a service agent address from
memory.** An earlier draft guessed `billing-budgets@` — singular "budget",
"alert" not "alerts" — and that address does not exist.

---

## 6. Cleanup

**Exempt from teardown, deliberately.** `scripts/cleanup.sh` does not destroy the
export or the budget: a cost guardrail that only exists during the week it was
built is not a guardrail, and every later week's `$0` claim is provable only
because this export keeps running.

If you do tear it down, remove the budget first and the org policy exception
last — the exception is what allows the budget's notification binding to exist.

**Cost:** the export is free; BigQuery storage for it is kilobytes. The budget
itself is free.

---

## 7. Troubleshooting

### `Error 400: Precondition check failed`

**Cause.** Domain restricted sharing. Cloud Billing is trying to write its own
Google-owned service agent onto your topic and the constraint refuses it.

**Fix.** Project-scoped exception to `iam.allowedPolicyMemberDomains`, plus a
120-second wait before writing the budget.

**How it was diagnosed**, since the error names nothing: by elimination. A bogus
topic produced `NOT_FOUND`, so resolution worked. Two different budgets produced
the identical failure, so it was not the budget. `testIamPermissions` confirmed
`setIamPolicy` was held, so it was not the caller. Identical as the pipeline
identity and as a human organization admin ⇒ an organization-level cause.

**Lesson.** Diagnose an opaque error by elimination, not by re-reading
documentation.

### `gcloud billing accounts add-iam-policy-binding` fails with INVALID_ARGUMENT

**Cause.** It echoes back `auditConfigs: []`, which the API rejects, and names no
argument.

**Fix.** `scripts/grant-billing-role.sh` — read-modify-write over REST.

### Two identities each hold half of what you need

**Cause.** The Gmail identity has `billing.admin` but no
`serviceusage.services.use` on the org-owned project; the Workspace account has
the project but only `costsManager`. The CLI cannot bridge that without widening
one of them.

**Fix.** The console supplies its own quota project and can.

---

## 8. Known limitations

- **The export link is configured by hand.** Not automatable, confirmed by
  attempting it; the form issues no save request under automation.
- **Re-pointing an export strands its history.** The old table stops receiving
  rows and the new dataset backfills at most one month, which is why the
  detailed export was left in the seed project rather than consolidated.
- **A multi-region dataset backfills; a single-region one does not.**
- **A detailed export is a strict superset of a standard export.** Running both
  stores a subset twice and bills twice. The standard dataset was deleted before
  it took a row.

---

## 9. For production

| Area | What would change |
| --- | --- |
| Alerting | Route the Pub/Sub topic somewhere a human reads; a topic nobody subscribes to is not an alert |
| Caps | Budgets alert, they do not cap. Spend caps exist (Preview, July 2026) but cover only Gemini API, Agent Platform, Cloud Run and Cloud Run functions |
| Exceptions | Review the domain-restricted-sharing exception periodically — it is a deliberate hole in a security control |
| Attribution | Labels and per-project budgets, since billing is orthogonal to the resource hierarchy |

---

## 10. References

- [Export billing data to BigQuery](https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery)
- [Budgets and alerts](https://docs.cloud.google.com/billing/docs/how-to/budgets)
- [Programmatic budget notifications](https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications)
- [Restricting identities by domain](https://docs.cloud.google.com/resource-manager/docs/organization-policy/restricting-domains)

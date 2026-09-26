# Screenshot plan — Week 06

Ordered by **what the post cannot be published without**, then by the order the
post walks through them. Where capture order and publish order conflict, capture
wins — a policy state stops existing the moment it is changed, and a paragraph
can be moved later.

Capture with `scripts/screenshots/capture_gcp.py` attached over CDP to the Chrome
that `scripts/screenshots/start-capture-chrome.bat` opens. Export `GCP_ORG_ID`,
`GCP_BILLING_ACCOUNT` and `GCP_PROJECT_NUMBERS` first; the script refuses to
write a file if any survive redaction, and it now discovers and masks the
signed-in account's address as well.

---

## 1 — The load-bearing shot

**`02-budget-pubsub-attached.png`** — the budget's Manage notifications section,
with the topic connected.

This is the week. It carries three things in one frame:

- `Connect a Pub/Sub topic to this budget`, checked, with
  `projects/katta698-gcp-logging/topics/billing-budget-notifications` selected —
  the thing that failed four times before the override existed.
- Google's own warning, in the console, in plain words: *"It may not be possible
  to add a Pub/Sub topic if it belongs to an organization that has domain
  restricted sharing enabled."* The API's version of that sentence is
  `Precondition check failed`. Showing both is the post's argument about error
  quality, made without a word of commentary.
- The four threshold rules, which prove the budget is the one Terraform manages.

Captured with `--click-text "Manage notifications"`, because the section is below
the fold and the console scrolls an inner container that `--full-page` does not
reach.

## 2 — The premise correction

**`01-export-already-running.png`** — the billing export page, showing
**Detailed usage cost: Enabled** against a dataset in the seed project, with
Standard, Pricing, FOCUS and CUD all Disabled.

The week's plan said the lab had no queryable cost record. This is the evidence
it already did, and had since July. Without this shot the post's central
correction is an assertion.

It also shows the pricing export still disabled, which the post has to explain
rather than hide — see Outstanding in the README.

## 3 — The guardrail, scoped rather than lifted

**`03-drs-override-scoped.png`** — the Domain restricted sharing policy details
for the logging project.

The three lines that matter are all visible: `Applies to: Project "Logging"`,
`Policy source: Override parent's policy`, `Policy enforcement: Replace parent`.
That is the difference between scoping an exception and switching a control off,
and a reader who only hears "we allowed all" will assume the worse one.

## 4 — The apply

**`04-hcp-apply.png`** — the successful run, and the standing evidence that this
week ran with no Google Cloud credential on the machine that started it.

**Not yet captured.** The capture profile's HCP session had lapsed and the script
refused to save the login page, which is the guard working. Needs a sign-in to
`app.terraform.io` in the capture Chrome.

---

## What has no screenshot, and should not pretend to

- **The service agent Cloud Billing publishes as.** The finding is a single line
  of an IAM policy, read back from the API:
  `serviceAccount:billing-budget-alert@system.gserviceaccount.com`. The console
  renders it inside a collapsed role row in a side panel; a screenshot of that is
  strictly less legible than the two lines quoted in the post. Same call as Week
  05's field probe.
- **The four diagnostic probes.** `NOT_FOUND` versus `FAILED_PRECONDITION` across
  two budgets and two identities is a table, not a picture. It belongs in the post
  as the table in the README.
- **The `$0.006` query result.** A `bq query` in a terminal. The number matters,
  the terminal chrome does not.
- **The billing-account permission wall.** The console renders it as a transient
  inline notice on a page that otherwise looks normal, so a capture of it reads as
  a screenshot of nothing. Quoted as text instead.

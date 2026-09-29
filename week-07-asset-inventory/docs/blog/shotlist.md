# Screenshot plan — Week 07

Four shots. The post is deliberately short this week, so each one has to carry a
step rather than decorate it.

Capture with `scripts/screenshots/capture_gcp.py` over CDP. Export `GCP_ORG_ID`,
`GCP_BILLING_ACCOUNT` and `GCP_PROJECT_NUMBERS` first.

---

**`01-hcp-apply.png`** — the HCP run, applied. The deployment step, and the
standing evidence that this ran with no Google credential on the machine that
started it.

Shows `Applied`, 9 resources, Terraform v1.14.8 — and four errored runs above
it. Those stay in frame on purpose: they are the three permission failures this
week is largely about, and cropping to the successful run would make the build
look smoother than it was.

**`02-bq-snapshot.png`** — the `hierarchy` table in BigQuery, showing its schema.

The schema is the point, not the rows: `ancestors` is a REPEATED field, which is
what makes "which projects are not in a folder" a one-line query. Note also that
Terraform created the dataset and not this table — the export did. The Week 06
`billing_pricing` dataset is visible in the same tree, which is the continuity
worth pointing at.

Captured with the `ws=` workspace URL; the plain `?d=&t=` form renders "Request
contains an invalid argument" behind a welcome modal, and `--click-text "Done"`
dismisses the modal.

**`03-pubsub-topic.png`** — the topic the feed publishes to.

**`04-asset-dashboard.png`** — the Asset Inventory console, resource counts by
type and by project.

Carries two things at once: the shape of the organization, and the line
**"Overview data last updated: September 23, 2026"** — while the export beside
it was minutes old. That single line is why the post tells you to query the
snapshot rather than read the dashboard.

---

## What has no screenshot, and should not pretend to

- **The audit results.** Two SQL queries and their output. A table in the post is
  more legible than a picture of a console query editor, and it is the answer
  that matters rather than the act of asking.
- **The feed firing.** A folder was created and a Pub/Sub message arrived in
  under 25 seconds. That is a terminal round-trip; the decoded message body
  belongs in the post as a code block.
- **The 403s.** Three permission failures shaped this week and all three are
  error text, quoted directly.

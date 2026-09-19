# Screenshot plan — Week 05

Ordered to match the **order of deployment**, because that is the order the post
walks through and a reader following along should never see a screenshot of
something that has not been built yet.

Two separate orderings matter and they are not the same:

- **Capture order** — what must be photographed before state moves past it.
- **Publish order** — where each image sits in the post.

Where they conflict, capture wins. A dry-run constraint stops existing the
moment it is enforced; a paragraph can be moved later.

Capture with `scripts/screenshots/capture_gcp.py` attached over CDP to the
Chrome that `scripts/screenshots/start-capture-chrome.bat` opens, signed in as
`katta698@jayanthkatta.com`. Export `GCP_ORG_ID`, `GCP_BILLING_ACCOUNT` and
`GCP_PROJECT_NUMBERS` first — the script refuses to write a file if any survive
redaction.

---

## 1 — The problem, before anything is built

**`01-billing-at-cap.png`** — the billing account's linked projects, at the cap.
This is the week's constraint and the reason Week 04's spoke had to be deleted.
Without it, "we deleted last week's project" reads as carelessness rather than
as the only option.

Billing → Account management, or the projects list filtered to the account.

## 2 — What CI could not do

**`02-hcp-week02-run.png`** — the Week 02 workspace run that added `tagAdmin`,
`tagUser` and `essentialcontacts.admin`. Evidence for the post's spine: the CI
identity could not build this week, and the grants went into the human-run layer
rather than into Week 05's own configuration.

HCP → `gcp-week-02` → the 2026-09-19 runs.

## 3 — The tag key and its closed values

**`03-tag-key-values.png`** — `environment` with exactly `dev` and `prod`.
The closed set is the point: the module is handed a value ID and cannot invent
one, which is what stops `env = prod-ish` becoming a tag no policy reads.

IAM & Admin → Tags, at the organization.

## 4 — The project the factory built

**`04-project-labels.png`** — `katta698-gcp-dev-app-02`, showing its labels.
Note `goog-terraform-provisioned=true` is added by the provider, not the module;
say so in the caption or a reader will assume it is ours.

**`05-project-tag-binding.png`** — the same project's `environment=dev` tag.
Paired with the labels shot deliberately: the post argues labels and tags are
not redundant, and two images of the same project carrying both is the cheapest
way to show it.

**`06-essential-contacts.png`** — SECURITY and TECHNICAL subscribed. The control
most obviously worth centralising: easy, invisible when missing, and nothing
breaks until the one day it matters.

## 5 — The constraint, and the thing it cannot read

**`07-constraint-dry-run.png`** — `custom.requireProjectNamingAndParent` in the
dry-run list, with its condition visible.

**Time-sensitive.** The dry-run state disappears the moment it is promoted.
Capture before any enforce flip, not after.

The rejection that produced this design — `resource.labels` refused with
`Error 400: Request has invalid values` — is terminal output, not a console
page. It belongs in the post as a code block, and the probe table alongside it.
No screenshot exists or can.

## 6 — The apply

**`08-hcp-week05-applied.png`** — the successful run. Also the standing evidence
that this week ran with no Google Cloud credential on the machine that started
it.

---

## What has no screenshot, and should not pretend to

- The field probe (`projectId` accepted, `labels` rejected). Terminal only.
- The `tagAdmin` / `tagUser` split. It is two role definitions read with
  `gcloud iam roles describe`; a screenshot of a permission list is less legible
  than the two lines quoted in the post.
- The billing quota increase form. Not filed.

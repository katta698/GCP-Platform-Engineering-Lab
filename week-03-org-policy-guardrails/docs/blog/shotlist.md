# Screenshot plan — Week 03

Written before the deployment finished, on the Week 02 lesson: five of that
week's six screenshots were captured, and the missing one was the denial — the
single image the whole post rested on. Capturing the easy ones first and the
load-bearing one last is how that happens. So this list is ordered by **what the
post cannot be published without**, not by the order the deploy produces them.

Capture with `scripts/screenshots/capture_gcp.py`, attached over CDP to the
Chrome that `scripts/screenshots/start-capture-chrome.bat` opens, signed in as
`katta698@jayanthkatta.com`. Set `GCP_ORG_ID`, `GCP_BILLING_ACCOUNT` and
`GCP_PROJECT_NUMBERS` in the environment first so redaction has something to
match; the script refuses to write the file if any survive.

---

## Load-bearing — the post is not publishable without these

**01 — the denial.** A bucket creation refused by the custom constraint, after
that constraint is flipped to enforced. This is the week's proof. Everything else
is context.

Must be attempted as `katta698@jayanthkatta.com`, which holds the permission to
create the bucket. Week 02's note applies unchanged: an attempt made by an
identity that lacks permission fails with a permission error, which looks like
success and proves nothing.

**02 — the same request succeeding with labels attached.** The denial alone does
not show the rule is *correct*, only that something was refused. The pair does.

**03 — a constraint in dry run, in the console**, showing it evaluated and denied
nothing. The dry-run state is the week's whole method, and it is the state most
easily confused with enforcement in a summary view.

**04 — the dry-run violation in Logs Explorer.** The log entry that says a
request *would* have been denied. This is what makes dry run useful rather than
merely safe, and it is the evidence that the enforce flip was informed rather
than assumed.

---

## Structural — the argument is much weaker without these

**05 — the organization's policy list**, new constraints alongside the seven
inherited ones. Shows what was already there versus what this week added, which
is the framing of the whole post.

**06 — the dev folder's serial-port override**, showing enforcement off at
`workloads/dev` while the organization has it on. The exception made visible.

**07 — the custom constraint definition page**, showing the CEL condition,
resource type and method types.

---

## Failure evidence — already preserved, capture at leisure

These are safe. Both runs are stored in HCP with full logs and can be
screenshotted any time.

**08 — `run-3k6cGfbT7WRCe9Zg`**, the `SERVICE_DISABLED` failure on
`orgpolicy.googleapis.com`, following a plan that had reported no problems.

**09 — `run-AmbgjjPkvidJFojq`**, the 409 `CONCURRENT_POLICY_CHANGES` failure.

Run URLs are `https://app.terraform.io/app/katta/workspaces/gcp-week-03/runs/<id>`.

The third failure — HCP refusing `-parallelism=1` — produced no run and exists
only as terminal text. It is transcribed in `evidence-terminal.md` and is not
recoverable by re-running.

**10 — the successful apply**, run log showing the full resource count and the
elapsed time. Also the standing evidence that this week ran with no GCP
credential anywhere: the workspace holds a workload provider name and two service
account emails, and no key.

---

## Measurement, capture when run

**11 — the custom constraint name-reuse result.** Delete the custom constraint,
attempt to recreate it under the same name, capture whichever way it goes. Two
Google documentation pages contradict each other on this, which is why it is a
measurement for this lab rather than a sentence quoted from either.

Capture the timestamps. If reuse succeeds after a delay, the delay is the finding
and a screenshot without a clock in it does not carry it.

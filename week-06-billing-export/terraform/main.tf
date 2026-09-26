/*
 * Week 06 — Billing export and budget alerts.
 *
 * Every week of this lab has opened with a cost note, and five of them have
 * claimed $0. Asked to prove one of those figures, the only available answer was
 * to open the billing console and read a summary off the screen.
 *
 * The first draft of this file said the lab had no queryable source for any of
 * those claims, and that this week would build one. That was wrong, and finding
 * out how it was wrong is the more useful half of the week.
 *
 * A detailed usage cost export was ALREADY running, into a dataset in the seed
 * project, and had been since 2026-07-01. Nobody had queried it. Asked on
 * 2026-09-26 what this lab has cost since July, it answers in one query:
 *
 *   2294 rows, 4 projects, 2026-07-01 to 2026-09-26, $0.006 total
 *
 * So the five $0 claims were true, and had been provable for three months. The
 * gap was never the export. It was that no one had pointed a query at it.
 *
 * That reshapes what is left to build. The detailed export is a SUPERSET of the
 * standard one — same fields plus resource-level cost — so the standard export
 * this file originally created was duplicate storage for data already held.
 * It is gone. What remains genuinely additive is the pricing export, which
 * answers what a thing COSTS rather than what was spent, and the alerting path.
 *
 * ---------------------------------------------------------------------------
 * What is NOT in this file, and cannot be
 *
 * Enabling Cloud Billing export to BigQuery is a CONSOLE-ONLY action. There is
 * no gcloud command, no Terraform resource, and no public REST endpoint —
 * /v1/billingAccounts/{id}/exportSettings returns 404. Confirmed 2026-09-22
 * against the provider's own schema (`terraform providers schema -json` lists
 * nine google_billing_* and google_logging_billing_* resources and no export
 * among them) and against Google's own terraform-google-billing-dashboard
 * module, which creates the datasets and then instructs the operator to link
 * them by hand.
 *
 * So this configuration builds the destination and the alerting path, and the
 * link between the billing account and the dataset is made once, in the console,
 * by a human. That is not a shortcut taken here; it is the only path Google
 * offers.
 *
 * The consequence for teardown is stated in cleanup.sh rather than discovered:
 * destroying the dataset does not unlink the export, because unlinking is also
 * console-only.
 * ---------------------------------------------------------------------------
 */

# ---------------------------------------------------------------------------
# APIs
#
# On the data project, because that is where the datasets and the topic live.
# ---------------------------------------------------------------------------

resource "google_project_service" "data" {
  for_each = toset([
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
  ])

  project            = var.data_project_id
  service            = each.value
  disable_on_destroy = false
}

# Budgets are a client-based API billed to the caller's quota project, which is
# the seed project for this week — same reasoning as Week 04's provider block.
resource "google_project_service" "seed" {
  for_each = toset([
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    # Pub/Sub, on the QUOTA project, even though the topic lives in the data
    # project. user_project_override attributes every call here, so the API has
    # to be on in a project that never holds a topic. Fourth week running that
    # this cascade has claimed another API; expect one per new service.
    "pubsub.googleapis.com",
  ])

  project            = var.seed_project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Where the billing data lands
#
# MULTI-REGION, and this is the decision that cannot be revisited.
#
# A multi-region dataset backfills the previous month when the export is first
# enabled — up to five days for that initial load. A single-region dataset
# captures nothing before the moment it was enabled, and no later change brings
# that history back. Five weeks of this lab's spend either exists in the table or
# does not, on the strength of this one argument.
#
# The lab bills $0, so the backfill recovers nothing of value in money terms. It
# recovers something more useful: a month of SKU and project rows proving the
# export works and the queries are right, on a table that would otherwise sit
# empty and unverifiable.
#
# Deletion protection off deliberately. The data is reproducible from Google's
# side by re-linking the export, the dataset holds nothing irreplaceable, and a
# lab that cannot tear down its own work accumulates cost and confusion.
# ---------------------------------------------------------------------------

# There is no standard-usage-cost dataset here, and its absence is the week's
# first real decision rather than an omission.
#
# An earlier draft created one. Google's own table reference settles that the
# detailed export "includes all of the data fields from the standard usage cost
# table, along with additional fields that provide resource-level cost data" —
# so with a detailed export already running, a standard export stores a strict
# subset of data the account is already keeping, in a second dataset, billed
# again. The correct number of standard exports to run alongside a detailed one
# is zero.
#
# The detailed export stays where it already is, in the seed project, and this
# configuration deliberately does not move it. Re-pointing an export does not
# carry history across: the old table stops receiving rows and the new dataset
# backfills at most the previous month. Tidiness would have cost July and August.
resource "google_bigquery_dataset" "billing_pricing" {
  project    = var.data_project_id
  dataset_id = "billing_pricing"
  location   = var.dataset_location

  friendly_name = "Cloud Billing export — pricing data"
  description   = "Destination for the pricing export: SKUs, tiers and units. Answers what a thing costs, as opposed to what was spent."

  delete_contents_on_destroy = true

  labels = {
    week       = "06"
    env        = "shared"
    managed-by = "terraform"
  }

  depends_on = [google_project_service.data]
}

# ---------------------------------------------------------------------------
# The budget's notification path
#
# A topic rather than only an email address, and the difference is larger than
# it looks. Budgets publish to Pub/Sub SEVERAL TIMES A DAY carrying the current
# cost against the budget — not only when a threshold is crossed. Email fires on
# breach; the topic is a cost feed.
#
# Nothing subscribes to it this week. That is deliberate: a subscriber is a
# design decision about what should happen to spend, and inventing one before
# there is any spend to react to would be building a mechanism for an
# unobserved problem.
# ---------------------------------------------------------------------------

resource "google_pubsub_topic" "budget" {
  project = var.data_project_id
  name    = "billing-budget-notifications"

  labels = {
    week       = "06"
    env        = "shared"
    managed-by = "terraform"
  }

  depends_on = [google_project_service.data]
}

# No hand-written publisher binding here, and that was a correction.
#
# The first draft granted roles/pubsub.publisher to
# billing-budgets@system.gserviceaccount.com, guessed from the shape other
# Google service agents take. It does not exist:
#
#   Error 400: Service account billing-budgets@system.gserviceaccount.com does not exist
#
# The address is not published in Google's own documentation. What the docs
# actually require is that the CALLER holds permission to grant Publisher on the
# topic — because Cloud Billing adds the binding itself when a topic is attached
# to a budget. So the correct move is to grant nothing here, let the budget
# creation do it, and then READ the topic's IAM policy to find out which identity
# Google used. That is in validate.sh, and it is a measurement rather than a
# guess repeated with more confidence.
#
# Measured 2026-09-26, immediately after the attach succeeded:
#
#   roles/pubsub.publisher
#     serviceAccount:billing-budget-alert@system.gserviceaccount.com
#
# Singular "budget", and "alert" rather than "budgets". Close enough to the guess
# to look right in a diff and wrong enough to fail, which is the argument for
# never writing a service agent address from memory. Note also that the binding
# is the ONLY one on the topic — the project's own editors get no publish rights
# here, so this policy is exactly as wide as the integration needs.

# ---------------------------------------------------------------------------
# The guardrail this week had to scope, and why
#
# Attaching the topic to the budget failed with:
#
#   Error 400: Precondition check failed.
#
# which names no resource, no permission and no policy. What it means is that
# Cloud Billing could not write to the topic's IAM policy. Attaching a topic to
# a budget is not a reference — Cloud Billing adds its own Google-owned service
# agent to that topic as a publisher. Week 03 enforced
# iam.allowedPolicyMemberDomains org-wide, restricted to this Workspace customer
# ID, and a Google-owned principal is by definition outside it. The IAM write was
# refused and the refusal was reported as a precondition.
#
# The diagnosis was measured, not assumed. Four observations pinned it:
#
#   bogus topic name     -> NOT_FOUND       (so the API does resolve the topic)
#   real topic, budget A -> FAILED_PRECONDITION
#   real topic, budget B -> FAILED_PRECONDITION   (so it is not the budget)
#   testIamPermissions   -> setIamPolicy HELD     (so it is not the caller)
#
# Identical as tf-apply and as a human org admin. A cause that survives all four
# is org-level, and Google's own budget-notification guidance confirms it:
# organization policies that limit resource sharing by domain break this, and the
# fix is to override the constraint for the project holding the topic.
#
# Scoped to THAT ONE PROJECT, not lifted org-wide. Every other project in this
# organization keeps Week 03's restriction. This is the shape a guardrail
# exception should take: narrow, in code, and next to the reason.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "drs_exception" {
  name   = "projects/${var.data_project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${var.data_project_id}"

  spec {
    # Overrides the inherited org rule for this project only. A list constraint
    # cannot name "Google's own service agents" as an allowed value — the agent's
    # address is not published, which is why guessing at it failed earlier — so
    # the exception is expressed as scope rather than as membership.
    inherit_from_parent = false

    rules {
      allow_all = "TRUE"
    }
  }
}

# Organization policy changes do not take effect instantly. Week 03 measured that
# lag rather than quoting it, and the same lag applies in reverse here: the
# budget attach below will keep failing with the same opaque precondition if it
# races the relaxation.
resource "time_sleep" "drs_propagation" {
  depends_on      = [google_org_policy_policy.drs_exception]
  create_duration = "120s"
}

# ---------------------------------------------------------------------------
# The budget
#
# The bootstrap already created one, "GCP lab guardrail", alerting by email at
# 50/90/100% of actual spend and 100% of forecast. This one does not replace it;
# it adds the programmatic path the original had no way to reach.
#
# On what a budget can and cannot do — corrected, because the obvious claim is
# now out of date. Spend caps shipped in Preview on 27 July 2026 and genuinely
# pause services. They do not apply here: eligible services are the Gemini API,
# Gemini Enterprise Agent Platform, Cloud Run and Cloud Run functions, and this
# lab runs none of them. For Compute Engine, Cloud Storage and BigQuery a budget
# is still an alert and nothing more, and Google will keep billing past it.
# ---------------------------------------------------------------------------

resource "google_billing_budget" "programmatic" {
  billing_account = var.billing_account
  display_name    = "GCP lab guardrail - programmatic"

  budget_filter {
    calendar_period        = "MONTH"
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic   = google_pubsub_topic.budget.id
    schema_version = "1.0"
  }

  # Not an ordering nicety. Without the wait this resource fails with the same
  # unnamed precondition the week started with.
  depends_on = [time_sleep.drs_propagation]
}

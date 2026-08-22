locals {
  labels = {
    week       = "bootstrap"
    env        = "shared"
    managed-by = "terraform"
  }

  # APIs the seed project itself needs. Per-week APIs are enabled by that week's
  # own configuration, not here.
  seed_apis = [
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "billingbudgets.googleapis.com",
  ]
}

# ---------------------------------------------------------------------------
# Seed project
# ---------------------------------------------------------------------------

resource "google_project" "seed" {
  name       = "GCP Lab Seed"
  project_id = var.seed_project_id

  # org_id is null under Option A (no organization). Terraform omits the
  # attribute rather than sending null, so the project is created standalone.
  org_id          = var.org_id
  billing_account = var.billing_account

  labels = local.labels

  # Deleting the project that holds all remote state should never be a
  # one-command accident.
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_service" "seed" {
  for_each = toset(local.seed_apis)

  project = google_project.seed.project_id
  service = each.value

  # Disabling an API on destroy can cascade into unrelated resources that also
  # depend on it, so this stays enabled once turned on.
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Budget guardrail
#
# Deliberately here in the bootstrap rather than in the week that covers billing
# properly. A budget is worth nothing on the day you get round to it; it is worth
# something on every day before that. This is the cheap version — a threshold
# alert to whoever holds billing roles — and Week 05 replaces it with budgets
# wired to Pub/Sub and a BigQuery billing export.
#
# Note this is an ALERT, not a cap. Google Cloud does not stop spending when a
# budget is exceeded; nothing here prevents a runaway cost, it only tells you.
# ---------------------------------------------------------------------------

resource "google_billing_budget" "lab" {
  billing_account = var.billing_account
  display_name    = "GCP lab guardrail"

  budget_filter {
    # No projects filter: this covers every project on the billing account,
    # including ones no week has created yet. A per-project budget would silently
    # miss exactly the runaway it is meant to catch.
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  # Actual spend, climbing.
  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  # Forecast, so the warning arrives while there is still time to act rather
  # than after the money is spent.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.seed]
}

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

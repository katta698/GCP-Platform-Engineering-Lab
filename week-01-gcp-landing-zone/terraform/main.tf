/*
 * Week 01 — Landing zone.
 *
 * Creates the resource hierarchy the rest of the lab sits inside. The shape is
 * argued for in docs/HIERARCHY.md; the short version is that a governance /
 * workload split maps onto FOLDERS in Google Cloud, not onto projects, because
 * a project here is a free, disposable unit that owns IAM, quota and API
 * enablement rather than a heavyweight account boundary.
 */

# ---------------------------------------------------------------------------
# Folders
# ---------------------------------------------------------------------------

resource "google_folder" "platform" {
  display_name = "platform"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "workloads" {
  display_name = "workloads"
  parent       = "organizations/${var.org_id}"
}

# dev and prod are folders rather than a label on a project because the whole
# point of the split is that policy attaches to it. An org policy on
# folders/workloads/prod constrains every project below it, including projects
# that do not exist yet. A label constrains nothing.
resource "google_folder" "dev" {
  display_name = "dev"
  parent       = google_folder.workloads.name
}

resource "google_folder" "prod" {
  display_name = "prod"
  parent       = google_folder.workloads.name
}

# ---------------------------------------------------------------------------
# Platform projects
#
# Split by blast radius, not by convenience. Whoever can rotate a KMS key should
# not thereby be able to rewrite the network, and whoever can read every log line
# in the estate should not be able to do either.
# ---------------------------------------------------------------------------

module "network_hub" {
  source = "./modules/project-factory"

  project_id      = var.network_hub_project_id
  display_name    = "Network Hub"
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
  week            = "01"
  env             = "shared"

  # compute is what makes this a Shared VPC host project in Week 12. dns is here
  # because private zones are owned by the host project, not by the service
  # projects that resolve against them.
  activate_apis = [
    "compute.googleapis.com",
    "dns.googleapis.com",
    "networkmanagement.googleapis.com",
  ]
}

module "logging" {
  source = "./modules/project-factory"

  project_id      = var.logging_project_id
  display_name    = "Logging"
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
  week            = "01"
  env             = "shared"

  # The sink destination has to exist before the org-level sink in Week 48.
  activate_apis = [
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
  ]
}

module "security" {
  source = "./modules/project-factory"

  project_id      = var.security_project_id
  display_name    = "Security"
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
  week            = "01"
  env             = "shared"

  # Security Command Center is activated at the organization, not here — this
  # project holds the key rings and the findings-export plumbing.
  activate_apis = [
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

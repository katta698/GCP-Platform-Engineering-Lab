/*
 * Week 07 — Resource hierarchy audit and drift.
 *
 * Six weeks of this lab have built a hierarchy: folders, projects, policies,
 * a Shared VPC, a project factory, a billing export. Asked "what exists in this
 * organization right now, and what changed since yesterday", the only honest
 * answer so far has been to open the console and look.
 *
 * Cloud Asset Inventory answers both, in two different shapes:
 *
 *   snapshot  — export the whole hierarchy to BigQuery and query it.  What IS.
 *   feed      — publish every change to Pub/Sub as it happens.        What CHANGED.
 *
 * Only one of those is declarative. The feed is a Terraform resource. The
 * snapshot export is an operation you invoke, not a resource you own, so it
 * lives in scripts/snapshot.sh rather than here. That split is the week's one
 * real lesson and it is the same shape as Week 06's console-only export link:
 * a thing can be fully automatable and still not be Terraform-shaped.
 */

resource "google_project_service" "asset_api" {
  for_each = toset([
    var.seed_project_id, # quota project: every CAI call is attributed here
    var.data_project_id, # destination project: holds the dataset and the topic
  ])

  project            = each.value
  service            = "cloudasset.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# What IS — snapshots land here
#
# One dataset, no tables. The tables are created by the export itself, named
# after the asset content type, and Terraform never sees them. Declaring them
# would be asserting a schema Google owns.
# ---------------------------------------------------------------------------

resource "google_bigquery_dataset" "assets" {
  project    = var.data_project_id
  dataset_id = "asset_inventory"
  location   = var.dataset_location

  friendly_name = "Cloud Asset Inventory — hierarchy snapshots"
  description   = "Destination for `gcloud asset export`. Tables are created by the export, not by Terraform."

  delete_contents_on_destroy = true

  labels = {
    week       = "07"
    env        = "shared"
    managed-by = "terraform"
  }

  depends_on = [google_project_service.asset_api]
}

# ---------------------------------------------------------------------------
# What CHANGED — the feed publishes here
#
# In the data project deliberately, and for a reason that survived being wrong
# about the details.
#
# The prediction was that this would fail exactly as Week 06 did: Cloud Billing
# adds its OWN service agent to a topic as publisher, and Week 03's domain
# restricted sharing constraint refuses Google-owned principals organization
# wide. Week 06 scoped an exception to this one project to get past it.
#
# Cloud Asset Inventory does not do that. It refuses to create the feed at all
# until the caller has already granted its agent publisher — and it says so
# properly:
#
#   Fail to publish to projects/.../topics/asset-hierarchy-changes as feed
#   output destination using service account:
#   service-<PROJECT_NUMBER>@gcp-sa-cloudasset.iam.gserviceaccount.com
#   Error: PERMISSION_DENIED ... permission: pubsub.topics.publish
#
# Service account, permission and resource, all named. Week 06 got four words.
# Same integration shape, opposite division of responsibility, and a difference
# in error quality that is worth more than either feature.
#
# The placement still matters. The binding below adds a GOOGLE-OWNED principal
# to an IAM policy, which is the precise thing Week 03's constraint refuses.
# It only succeeds here because Week 06 scoped the exception to this project.
# ---------------------------------------------------------------------------

resource "google_pubsub_topic" "asset_changes" {
  project = var.data_project_id
  name    = "asset-hierarchy-changes"

  labels = {
    week       = "07"
    env        = "shared"
    managed-by = "terraform"
  }

  depends_on = [google_project_service.asset_api]
}

# The service agent's address is derived, never typed. Week 06 guessed one and
# guessed wrong; the reliable form is the project NUMBER of the quota project,
# which is what Cloud Asset Inventory calls as.
data "google_project" "seed" {
  project_id = var.seed_project_id
}

locals {
  # Cloud Asset Inventory writes to every destination as ITSELF, never as the
  # caller. That one sentence explains all three grants below: the operator
  # running an export needs permission to ASK for it, and the agent needs
  # permission to DELIVER it. Being project owner on the destination is not
  # enough and never becomes enough.
  asset_agent = "serviceAccount:service-${data.google_project.seed.number}@gcp-sa-cloudasset.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "asset_publisher" {
  project = var.data_project_id
  topic   = google_pubsub_topic.asset_changes.name
  role    = "roles/pubsub.publisher"
  member  = local.asset_agent
}

# Writes the snapshot rows. Scoped to the dataset rather than the project: the
# agent needs to write these tables and nothing else in the logging project.
resource "google_bigquery_dataset_iam_member" "asset_writer" {
  project    = var.data_project_id
  dataset_id = google_bigquery_dataset.assets.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.asset_agent
}

# Running the load is a separate permission from writing the rows, and it is
# only grantable at the project. Without it the export fails with the same
# unattributable 403 as having no access at all.
resource "google_project_iam_member" "asset_job_user" {
  project = var.data_project_id
  role    = "roles/bigquery.jobUser"
  member  = local.asset_agent
}

# ---------------------------------------------------------------------------
# The feed
#
# Scoped to projects and folders only. Watching every asset type in the
# organization would produce a message for every metadata write on every
# resource — the hierarchy changing is a rare, meaningful event, and burying it
# in noise is the same mistake as an alert that fires on everything.
# ---------------------------------------------------------------------------

resource "google_cloud_asset_organization_feed" "hierarchy" {
  billing_project = var.seed_project_id
  org_id          = var.org_id
  feed_id         = "hierarchy-changes"
  content_type    = "RESOURCE"

  asset_types = [
    "cloudresourcemanager.googleapis.com/Project",
    "cloudresourcemanager.googleapis.com/Folder",
  ]

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }

  # Not ordering for its own sake: the API verifies the publisher binding at
  # creation time and refuses the feed outright if it is missing.
  depends_on = [
    google_project_service.asset_api,
    google_pubsub_topic_iam_member.asset_publisher,
  ]
}

# Stage 2 - the rotator.
#
# Every resource in this file is gated on var.deploy_rotator, because the week's
# central measurement requires one rotation notification to fire with nothing
# subscribed to the topic. See the variable's description: the staging is the
# experiment, not a convenience.
#
# Apply once with deploy_rotator = false, take the measurement, then apply again
# with true.

locals {
  rotator = var.deploy_rotator ? 1 : 0
}

resource "google_project_service" "rotator" {
  for_each = var.deploy_rotator ? toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    # Cloud Functions gen2 stages its source in GCS and its image in Artifact
    # Registry; both are created by Google but the APIs are ours to enable.
    "storage.googleapis.com",
  ]) : toset([])

  project            = var.security_project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "source" {
  count = local.rotator

  # Bucket names are globally unique, so the project number would be the
  # conventional suffix - and this repository is public, so it is not available.
  # The project ID is already a variable kept out of git for the same reason.
  name     = "${var.security_project_id}-wk12-rotator-src"
  location = var.region
  project  = var.security_project_id

  # Week 03's baseline enforces uniform bucket-level access org-wide, so this is
  # not optional here. Set explicitly rather than inherited, so the config is
  # appliable in an organization that does not enforce it.
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = local.labels

  depends_on = [google_project_service.rotator]
}

data "archive_file" "rotator" {
  count       = local.rotator
  type        = "zip"
  source_dir  = "${path.module}/../rotator"
  output_path = "${path.module}/.rotator.zip"
}

resource "google_storage_bucket_object" "rotator" {
  count = local.rotator

  # The hash in the name is what makes a redeploy happen. Without it the object
  # name never changes, Cloud Functions sees the same source reference, and an
  # edited rotator is uploaded and then ignored.
  name   = "rotator-${data.archive_file.rotator[0].output_md5}.zip"
  bucket = google_storage_bucket.source[0].name
  source = data.archive_file.rotator[0].output_path
}

# ---------------------------------------------------------------------------
# The rotator's own identity
# ---------------------------------------------------------------------------

resource "google_service_account" "rotator" {
  count = local.rotator

  account_id   = "wk12-secret-rotator"
  display_name = "Week 12 secret rotator"
  description  = "Adds and disables versions of one secret. Holds no permission to READ any secret value."
  project      = var.security_project_id
}

# secretVersionAdder, scoped to the one secret, and NOT secretAccessor.
#
# Worth stating plainly because it is counter-intuitive: a rotator does not need
# to read the secret it rotates. It writes a new value; it never needs the old
# one. So the identity that handles this credential every hour cannot read it,
# and nothing is lost by that.
resource "google_secret_manager_secret_iam_member" "rotator_adder" {
  count = local.rotator

  secret_id = google_secret_manager_secret.app_db_password.secret_id
  project   = var.security_project_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = google_service_account.rotator[0].member
}

# Disabling the superseded version is a separate role from adding one - the same
# create-versus-modify split as Week 04's firewall policies and Week 05's tags.
resource "google_secret_manager_secret_iam_member" "rotator_manager" {
  count = local.rotator

  secret_id = google_secret_manager_secret.app_db_password.secret_id
  project   = var.security_project_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = google_service_account.rotator[0].member
}

# Eventarc delivers the Pub/Sub message, and it checks that the trigger's
# identity is allowed to receive events before it will create the trigger.
resource "google_project_iam_member" "rotator_event_receiver" {
  count = local.rotator

  project = var.security_project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.rotator[0].member
}

# ---------------------------------------------------------------------------
# The function
# ---------------------------------------------------------------------------

resource "google_cloudfunctions2_function" "rotator" {
  count = local.rotator

  name     = "wk12-secret-rotator"
  location = var.region
  project  = var.security_project_id

  build_config {
    runtime     = "python312"
    entry_point = "rotate"

    source {
      storage_source {
        bucket = google_storage_bucket.source[0].name
        object = google_storage_bucket_object.rotator[0].name
      }
    }
  }

  service_config {
    # Smallest instance Cloud Run offers. The function runs once an hour for
    # well under a second, so this is a rounding error against the free tier -
    # but max_instance_count is the line that matters, and it is 1 on purpose:
    # concurrent rotations of one secret are a race, and Secret Manager already
    # says "in-flight rotations must complete before another rotation can be
    # started".
    available_memory               = "256Mi"
    timeout_seconds                = 60
    max_instance_count             = 1
    min_instance_count             = 0
    service_account_email          = google_service_account.rotator[0].email
    all_traffic_on_latest_revision = true

    environment_variables = {
      SECRET_PROJECT = var.security_project_id
      SECRET_ID      = google_secret_manager_secret.app_db_password.secret_id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.rotation_events.id
    # A failed rotation that is silently dropped is worse than one that retries:
    # the secret stays stale and nothing says so. Secret Manager retries its own
    # notification for up to seven days, and this matches that posture.
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.rotator[0].email
  }

  labels = local.labels

  depends_on = [
    google_project_service.rotator,
    google_project_iam_member.rotator_event_receiver,
    google_secret_manager_secret_iam_member.rotator_adder,
    google_secret_manager_secret_iam_member.rotator_manager,
  ]
}

output "rotator_function" {
  description = "Rotator function name, or null while stage 1 is the deployed state."
  value       = var.deploy_rotator ? google_cloudfunctions2_function.rotator[0].name : null
}

output "rotator_identity" {
  description = "The rotator's service account. Note it holds secretVersionAdder and secretVersionManager, and NOT secretAccessor - it cannot read the secret it rotates."
  value       = var.deploy_rotator ? google_service_account.rotator[0].email : null
}

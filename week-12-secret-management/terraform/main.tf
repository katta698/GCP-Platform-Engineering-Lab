# Week 12 - Secret management: CMEK, and the two things both called "rotation".
#
# The week's claim, stated before any resource: a Secret Manager rotation
# schedule does not rotate a secret. It publishes a message and stops. Cloud KMS
# rotation, configured forty lines away in the same file, genuinely does
# generate a new key version by itself. Both are "rotation" in Google's own
# vocabulary, in the same console, in the same project.
#
# Everything lives in the platform security project from Week 01. Nothing here
# consumes the secret: a workload that read it would add a second thing to debug
# and prove nothing extra about the control.

locals {
  labels = {
    week       = "12"
    env        = "platform"
    managed-by = "terraform"
  }

  # Secret Manager encrypts and decrypts as ITSELF, never as the caller - the
  # same shape as Cloud Asset Inventory in Week 07 and Cloud Billing in Week 06.
  # Owning the key confers nothing; this agent needs its own grant on it.
  secretmanager_agent = google_project_service_identity.secretmanager.email
}

# Week 01 already enables cloudkms and secretmanager on this project and its
# workspace owns them, so they are deliberately NOT declared here - two
# workspaces owning one google_project_service is a fight, not a safety net.
# Pub/Sub is this week's addition.
resource "google_project_service" "pubsub" {
  project            = var.security_project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Must exist BEFORE the secret is created. A CMEK secret whose service agent
# does not yet exist fails at creation with a permission error on the key naming
# an account that has never existed.
resource "google_project_service_identity" "secretmanager" {
  provider = google-beta
  project  = var.security_project_id
  service  = "secretmanager.googleapis.com"
}

# ---------------------------------------------------------------------------
# Cloud KMS - the key, and the rotation that actually rotates
# ---------------------------------------------------------------------------

resource "google_kms_key_ring" "secrets" {
  name     = "wk12-secrets"
  location = var.key_location
  project  = var.security_project_id
}

resource "google_kms_crypto_key" "app_db_password" {
  name     = "wk12-app-db-password"
  key_ring = google_kms_key_ring.secrets.id
  purpose  = "ENCRYPT_DECRYPT"

  # SOFTWARE, not HSM, and the gap is two orders of magnitude: a software
  # version is $0.06/month against $1.00-$2.50 for HSM and $3,500/month for a
  # single-tenant HSM. Nothing in this lab justifies hardware custody, and the
  # control being demonstrated - who HOLDS the key - is identical either way.
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  rotation_period            = var.kms_rotation_period
  destroy_scheduled_duration = var.destroy_scheduled_duration

  labels = local.labels

  # The provider's own documentation is blunt about what destroy does here:
  # "CryptoKeys cannot be deleted from Google Cloud Platform. Destroying a
  # Terraform-managed CryptoKey will remove it from state and delete all
  # CryptoKeyVersions, rendering the key unusable, but will not delete the
  # resource from the project."
  #
  # prevent_destroy is deliberately NOT set, and that is a departure worth
  # naming. For a key holding real data the convention is right. Here the
  # teardown is the experiment: Google's documentation now says keys and key
  # rings can be deleted, the provider's note above says they cannot, one of
  # those is out of date, and the only way to find out which is to run it. The
  # secret this key protects is a value generated for the lab and used by
  # nothing.
}

resource "google_kms_crypto_key_iam_member" "secretmanager_encrypt_decrypt" {
  crypto_key_id = google_kms_crypto_key.app_db_password.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.secretmanager_agent}"
}

# ---------------------------------------------------------------------------
# Pub/Sub - mandatory, not optional
# ---------------------------------------------------------------------------

# Google's wording is "Pub/Sub topics must be configured on the secret." There
# is no rotation without a topic, because the notification IS the feature.
resource "google_pubsub_topic" "rotation_events" {
  name    = "wk12-secret-rotation-events"
  project = var.security_project_id
  labels  = local.labels

  depends_on = [google_project_service.pubsub]
}

# Without this the SECRET fails to create, not the rotation. Secret Manager
# validates at creation time that it can publish to every configured topic, so a
# missing publisher binding surfaces as a secret that will not exist.
resource "google_pubsub_topic_iam_member" "secretmanager_publisher" {
  topic   = google_pubsub_topic.rotation_events.name
  project = var.security_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.secretmanager_agent}"
}

# A pull subscription with no subscriber attached. This is the instrument for
# the week's central measurement: it catches the rotation notification and does
# nothing with it, so the message can be read back and the secret's version
# count shown unchanged beside it.
resource "google_pubsub_subscription" "observer" {
  name    = "wk12-rotation-observer"
  topic   = google_pubsub_topic.rotation_events.id
  project = var.security_project_id
  labels  = local.labels

  # Long enough that a notification is still retrievable when the measurement
  # script gets to it, rather than acked and gone.
  message_retention_duration = "86400s"
  ack_deadline_seconds       = 60
}

# ---------------------------------------------------------------------------
# The secret
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "app_db_password" {
  secret_id = "wk12-app-db-password"
  project   = var.security_project_id
  labels    = local.labels

  # AUTOMATIC replication, which is what forces the key to be global. The
  # alternative - user-managed replication naming each region, with a key in
  # each - buys nothing here and would make the CMEK location requirement look
  # like a choice rather than the constraint it is.
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.app_db_password.id
      }
    }
  }

  # THE FINDING. When next_rotation_time arrives, Secret Manager "triggers a
  # SECRET_ROTATE message to the designated Pub/Sub topics" and that is the
  # whole of it. No new version is created. No value changes. Nothing reads the
  # old value or writes a new one. Google says so directly: "You must configure
  # a Pub/Sub subscriber to receive and act on" the message.
  #
  # So these four lines schedule a reminder, and every consumer of this secret
  # keeps reading the same password forever unless something else is built.
  rotation {
    rotation_period    = var.rotation_period
    next_rotation_time = var.next_rotation_time
  }

  topics {
    name = google_pubsub_topic.rotation_events.id
  }

  depends_on = [
    google_pubsub_topic_iam_member.secretmanager_publisher,
    google_kms_crypto_key_iam_member.secretmanager_encrypt_decrypt,
  ]
}

# A generated value. Nothing in this lab is a real credential, and a hardcoded
# one in a public repo would be a worked example of the mistake the week is
# about.
resource "random_password" "initial" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret_version" "v1" {
  secret      = google_secret_manager_secret.app_db_password.id
  secret_data = random_password.initial.result
}

output "secret_id" {
  description = "Secret resource name. validate.sh counts versions on this and asserts the count does not move on a rotation notification."
  value       = google_secret_manager_secret.app_db_password.id
}

output "crypto_key_id" {
  description = "Full key resource name. Disabling its primary version is what proves CMEK is a kill switch rather than a label."
  value       = google_kms_crypto_key.app_db_password.id
}

output "rotation_subscription" {
  description = "Pull subscription that catches the SECRET_ROTATE notification without acting on it."
  value       = google_pubsub_subscription.observer.name
}

output "next_rotation_time" {
  description = "Echoed so the measurement script does not have to re-derive when to start watching."
  value       = google_secret_manager_secret.app_db_password.rotation[0].next_rotation_time
}

output "secretmanager_service_agent" {
  description = "The identity that performs every encrypt and decrypt. Owning the key is not enough; this account needs its own grant on it."
  value       = google_project_service_identity.secretmanager.email
}

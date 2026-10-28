output "entitlement_name" {
  description = "Full resource name of the entitlement. Needed to request a grant against it."
  value       = google_privileged_access_manager_entitlement.folder_security_review.name
}

output "subject_email" {
  description = "The service account that must hold nothing directly. validate.sh asserts exactly that."
  value       = google_service_account.jit_subject.email
}

output "max_request_duration" {
  description = "Echoed so the measurement script does not have to re-derive the expiry window."
  value       = google_privileged_access_manager_entitlement.folder_security_review.max_request_duration
}

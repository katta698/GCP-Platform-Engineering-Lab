# Everything below is marked sensitive. Not because any of it is a secret — a
# provider resource name is not — but because each value embeds the seed
# project's number, and these outputs are read on screen and screenshotted for
# the write-up. Sensitive keeps them out of the run log; `terraform output -raw`
# still prints one when it is needed.

output "workload_provider_name" {
  description = "Full provider resource name. This is TFC_GCP_WORKLOAD_PROVIDER_NAME in the HCP workspace."
  value       = google_iam_workload_identity_pool_provider.hcp.name
  sensitive   = true
}

output "plan_service_account" {
  description = "TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL."
  value       = google_service_account.plan.email
  sensitive   = true
}

output "apply_service_account" {
  description = "TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL, and the fallback TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL."
  value       = google_service_account.apply.email
  sensitive   = true
}

output "attribute_condition" {
  description = "The CEL expression enforced at token exchange. Worth reading back after an apply — a condition that silently failed to narrow is indistinguishable from one that worked, until someone else's token is accepted."
  value       = google_iam_workload_identity_pool_provider.hcp.attribute_condition
}

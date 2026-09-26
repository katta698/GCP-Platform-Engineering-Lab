variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value. The budget attaches here, not to a project."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = "Quota project for the client-based Billing and Budgets APIs. See the note in versions.tf."
  type        = string
}

variable "data_project_id" {
  description = <<-EOT
    Project holding the BigQuery datasets and the Pub/Sub topic.

    katta698-gcp-logging, created in Week 01 for exactly this kind of work and
    unused until now. It already carries the BigQuery API set. Using it means
    this week consumes no billing-account project slot, which matters because
    the account is at its five-project cap.
  EOT
  type        = string
}

variable "region" {
  description = "Default region. This week creates no regional compute; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

variable "dataset_location" {
  description = <<-EOT
    BigQuery location for the billing datasets. MULTI-REGION ("US") on purpose,
    and the choice is irreversible in effect:

      multi-region  backfills the previous month when the export is first
                    enabled, up to five days for that initial load
      single-region captures only from the moment of enablement forward, and
                    no later change recovers the gap

    A dataset's location cannot be changed after creation, so getting this wrong
    means creating a second dataset and re-linking the export.
  EOT
  type        = string
  default     = "US"
}

variable "budget_amount_usd" {
  description = "Budget amount in whole USD. Matches the bootstrap guardrail so the two agree on what 'over' means."
  type        = number
  default     = 25
}

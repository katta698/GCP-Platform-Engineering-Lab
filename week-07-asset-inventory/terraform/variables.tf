variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value. The feed watches the whole organization."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = "Quota project for the Cloud Asset Inventory API. See the note in versions.tf."
  type        = string
}

variable "data_project_id" {
  description = <<-EOT
    Project holding the BigQuery dataset and the Pub/Sub topic.

    katta698-gcp-logging again, and not only for tidiness: it already carries
    the project-scoped exception to iam.allowedPolicyMemberDomains that Week 06
    had to add. Cloud Asset Inventory adds its own service agent to the feed's
    topic as publisher, exactly as Cloud Billing did, so a topic anywhere else
    in this organization would be refused by that constraint.
  EOT
  type        = string
}

variable "region" {
  description = "Default region. This week creates nothing regional; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

variable "dataset_location" {
  description = "BigQuery location for the asset snapshots. US to match the billing export, so the two can be joined without a cross-region copy."
  type        = string
  default     = "US"
}

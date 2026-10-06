variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value. Both the custom role and the deny policy are organization-scoped."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = "Quota project for the IAM v2 API. See the note in versions.tf."
  type        = string
}

variable "plan_service_account" {
  description = "The read-only CI identity. Week 07 had to give it roles/cloudasset.owner because no predefined read-only role can read an asset feed; this week replaces that with a custom role carrying only what it needs."
  type        = string
  default     = "tf-plan@katta698-gcp-lab-seed.iam.gserviceaccount.com"
}

variable "apply_service_account" {
  description = "The CI identity that legitimately manages asset feeds. Exempted from the deny policy, or Week 07 stops being deployable."
  type        = string
  default     = "tf-apply@katta698-gcp-lab-seed.iam.gserviceaccount.com"
}

variable "break_glass_principal" {
  description = <<-EOT
    The human who can still delete a feed when something is actually on fire.

    Not optional. A deny policy with no exception is an outage waiting for the
    day you need the denied action, and the usual fix under pressure is to
    delete the whole policy — which removes the guardrail entirely instead of
    using it once. One named exception is safer than a policy people learn to
    switch off.
  EOT
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Default region. This week creates nothing regional; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

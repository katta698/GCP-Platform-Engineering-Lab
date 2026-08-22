variable "org_id" {
  description = <<-EOT
    Numeric organization ID. Leave null if you chose Option A in docs/SETUP.md
    (no Cloud Identity organization) — the seed project is then created
    standalone and folder-based weeks are unavailable.
  EOT
  type        = string
  default     = null
}

variable "billing_account" {
  description = "Billing account ID, format XXXXXX-XXXXXX-XXXXXX. Never commit this value."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = <<-EOT
    Globally unique project ID for the seed project that holds Terraform state
    and the CI identity. Must be 6-30 chars, lowercase letters, digits, hyphens.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.seed_project_id))
    error_message = "seed_project_id must be 6-30 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "budget_amount" {
  description = <<-EOT
    Monthly budget threshold in whole currency units. This is an alert level, not
    a spending cap — Google Cloud does not stop resources when it is crossed.
  EOT
  type        = number
  default     = 25
}

variable "budget_currency" {
  description = "Currency code for the budget. Must match the billing account's currency."
  type        = string
  default     = "USD"
}

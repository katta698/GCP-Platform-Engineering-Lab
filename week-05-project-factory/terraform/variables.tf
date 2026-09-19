variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = <<-EOT
    Quota project for the provider. Tag keys, tag values and custom constraints
    are organization-owned, so the client-based APIs behind them bill and quota
    against the caller's project — see the note in versions.tf.
  EOT
  type        = string
}

variable "region" {
  description = "Default region. This week creates no regional resource; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

variable "demo_project_id" {
  description = <<-EOT
    Project ID for the one project this week builds through the factory.

    Globally unique and permanent — an ID is never released for reuse, even
    after the project is deleted. So a rebuild of this week cannot reuse this
    value and will need the ordinal incremented, which is why the ID carries one
    rather than describing what the project is for.
  EOT
  type        = string
  default     = "katta698-gcp-dev-app-02"
}

variable "essential_contact_email" {
  description = <<-EOT
    Address that receives Google's operational notices — security bulletins,
    deprecation warnings, suspension notices — for projects the factory builds.

    Sensitive: never commit the value. Note the organization enforces
    essentialcontacts.managed.allowedContactDomains, inherited from Google's
    security baseline and scoped to this organization's domain, so an address
    outside it is refused at apply rather than accepted and silently ignored.
  EOT
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# The enforcement switch
#
# Empty of meaning until the constraint has logged something. The same rule
# Week 03 established: a constraint that has never evaluated a request has no
# evidence behind it, and enforcing on no evidence is a guess dressed as a
# control.
#
# The second reason has now been settled by measurement rather than left open:
# Project exposes resource.projectId and resource.parent to a custom constraint,
# and does NOT expose resource.labels or resource.displayName. The condition
# below is written only on the two that Google accepted.
# ---------------------------------------------------------------------------
variable "enforce_naming_constraint" {
  description = "false = dry run (logs, denies nothing). Flip to true only after reading a real violation in the audit log."
  type        = bool
  default     = false
}

variable "project_id_prefix" {
  description = <<-EOT
    Required prefix for every project ID in this organization. Enforced by the
    custom constraint, which can read resource.projectId — measured, because the
    reference does not publish which Project fields a custom constraint sees,
    and resource.labels turned out not to be among them.
  EOT
  type        = string
  default     = "katta698-gcp-"
}

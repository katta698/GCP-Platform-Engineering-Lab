variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

# Declared but not referenced by any resource, on purpose. The billing grant this
# week needs is made by a human out of band — see the note at the foot of
# main.tf. The variable stays so that scripts/validate.sh and the workspace
# variable set have somewhere to put the value, and so that removing the
# resource did not silently change what this workspace expects to be given.
variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = <<-EOT
    Project that owns the workload identity pool. The seed project, because CI
    identity is a bootstrap concern: the project that created the hierarchy also
    holds the identity that maintains it. Putting it in the security project
    would give that project org-level admin reach it has no other reason to have.
  EOT
  type        = string
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-central1"
}

# Lowercase, and that is not a typo. The organization's real name is "katta";
# "Katta" is what every human-facing surface shows — the console URL, the
# cloud {} block in versions.tf, the workspace list — because HCP routes and
# resolves those case-insensitively. The token claim carries the true value, and
# the CEL comparison Google runs against it is case-sensitive. So the two ends
# can disagree while both look right, and the only symptom is a rejected
# credential with no indication of which claim failed.
variable "hcp_organization" {
  description = "HCP Terraform organization name, exactly as it appears in the token's terraform_organization_name claim. Case-sensitive."
  type        = string
  default     = "katta"
}

variable "hcp_project_name" {
  description = "HCP Terraform project holding this lab's workspaces. Claim value is the display name, spaces included."
  type        = string
  default     = "GCP Platform Lab"
}

variable "workspace_prefix" {
  description = <<-EOT
    Only workspaces whose name starts with this may federate. The prefix is what
    keeps the AWS lab's workspaces — same HCP organization, same token issuer —
    from being able to reach this Google Cloud organization at all.
  EOT
  type        = string
  default     = "gcp-"
}

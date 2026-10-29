variable "seed_project_id" {
  description = "Seed project. Home of the demo service account and where the PAM API is enabled."
  type        = string
}

variable "platform_folder_id" {
  description = <<-EOT
    Folder the entitlement grants access on, in `folders/NNNN` form - the same
    shape every other week in this lab uses, and the shape the provider
    documents for `parent`. Do NOT add the prefix again at the use site.

    FOLDER rather than organization, for the same reason as Week 10 and not as a
    preference. Creating an entitlement requires setIamPolicy on its parent:
    roles/resourcemanager.organizationAdmin at the organization, or
    roles/resourcemanager.folderAdmin at a folder. `tf-apply` deliberately does
    not hold the former - an identity must not be able to grant itself anything
    - and does hold the latter.

    So the pipeline cannot write an organization-level entitlement and can write
    a folder-level one. Narrower is the right answer anyway; here it is also the
    only answer the pipeline can execute.
  EOT
  type        = string
}

variable "operator_principal" {
  description = <<-EOT
    The human who approves the grant and runs the test, as a bare email address.

    Load-bearing in two different ways.

    As APPROVER: if one principal both requests and approves, the approval step
    is a form filled in twice and proves nothing. Multi-party approval - the
    control that would make this structural rather than procedural - is in
    Preview and requires Security Command Center Premium or Enterprise, which
    this lab does not activate. A human approver distinct from the requester is
    the honest version available on the free tier.

    As IMPERSONATOR: the requester is a service account that holds nothing, and
    somebody has to mint a token as it to make the request at all. Granted
    roles/iam.serviceAccountTokenCreator on that one account and nothing else.

    A personal identifier, so it stays in terraform.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "elevated_role" {
  description = <<-EOT
    The role the entitlement grants, and the thing the subject must not hold
    permanently.

    roles/iam.securityReviewer reads every IAM policy in the subtree. It is a
    genuine example of the shape just-in-time access exists for: occasionally
    necessary, dangerous as a standing grant, and read-only so a lab can
    demonstrate it without risking anything.

    It also makes the test self-contained. The subject's check is to read the
    IAM policy of the very folder the entitlement is attached to, so while a
    grant is active it can see its own temporary binding - a binding that
    appears in the policy and is written by nothing in this configuration.
  EOT
  type        = string
  default     = "roles/iam.securityReviewer"
}

variable "max_request_duration" {
  description = <<-EOT
    Longest access a single grant can last, in seconds.

    Set to Google's documented MINIMUM. The supported range is 1800s to
    604800s, so 30 minutes is the shortest elevated access PAM will issue -
    there is no way to hand someone five minutes. That constraint is a finding
    of this week rather than a configuration choice, and it sets the floor on
    how long each expiry measurement takes.
  EOT
  type        = string
  default     = "1800s"
}

variable "region" {
  description = "Default region. This week creates nothing regional; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

variable "org_id" {
  description = <<-EOT
    Organization number. Needed only to address the Privileged Access Manager
    service agent, which is ORG-scoped even when the entitlement is attached to
    a folder: service-org-<ORG>@gcp-sa-pam.iam.gserviceaccount.com.

    An account identifier, so it lives in terraform.tfvars and never in git.
  EOT
  type        = string
  sensitive   = true
}

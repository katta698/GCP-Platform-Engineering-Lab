variable "name" {
  description = "Display name. Shown in the console and in the project picker; unlike project_id it can be changed later."
  type        = string
}

variable "project_id" {
  description = <<-EOT
    Globally unique across all of Google Cloud, and PERMANENT — a project ID
    cannot be changed after creation, and is not released for reuse when the
    project is deleted. That is why every ID this lab creates carries a prefix
    and an ordinal rather than a descriptive name that a rebuild would want back.
  EOT
  type        = string
}

variable "folder_id" {
  description = "Parent folder, in `folders/NNN` form. A project must be created under its intended parent — moving it later is possible but the org policies that were evaluated at creation are not re-evaluated."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "env" {
  description = "Environment this project belongs to. Becomes both a label (billing export, queryable) and a tag value (policy-conditionable). The two are not interchangeable and the module sets both deliberately."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod. The tag key created by the caller allows exactly these two values, and a tag binding to a value that does not exist fails at apply with a permission error rather than a not-found error."
  }
}

variable "week" {
  description = "Lab week that created this project. Part of the mandatory label set."
  type        = string
}

variable "apis" {
  description = <<-EOT
    APIs to enable, one google_project_service each. Explicit rather than
    inherited: there is no way to ask Google Cloud for "the usual set", and a
    project factory that enables a generous default is how projects acquire a
    blast radius nobody chose.
  EOT
  type        = list(string)
  default     = []
}

variable "environment_tag_value_id" {
  description = "Full resource name of the tag value to bind, e.g. tagValues/12345. Passed in rather than looked up, because the caller owns the tag key and the module must not be able to invent new values."
  type        = string
}

variable "essential_contact_email" {
  description = "Address that receives Google's non-marketing operational notices for this project. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "essential_contact_categories" {
  description = <<-EOT
    Which notification categories this contact receives. SECURITY and TECHNICAL
    are the two that carry outage and vulnerability notices; the default omits
    BILLING because billing already alerts through the budget configured in
    bootstrap, and duplicate channels for the same event train people to ignore
    both.
  EOT
  type        = list(string)
  default     = ["SECURITY", "TECHNICAL"]
}

variable "deletion_lien" {
  description = <<-EOT
    Whether to place a lien refusing resourcemanager.projects.delete.

    A lien is not an IAM control. It does not care who the caller is — an
    organization administrator with every role is refused exactly like anyone
    else, until the lien is removed as a separate, deliberate act. That property
    is the point: the usual project-deletion accident is committed by someone who
    genuinely held the permission.
  EOT
  type        = bool
  default     = false
}

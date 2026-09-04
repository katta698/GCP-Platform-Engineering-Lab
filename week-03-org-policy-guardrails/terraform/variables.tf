variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = <<-EOT
    Project the provider bills API calls against. Organization policy is not
    stored in a project — it hangs off the organization and folders — but the
    provider still needs a project to quote quota against, and the seed project
    is where this lab's control-plane work is already accounted.
  EOT
  type        = string
}

variable "region" {
  description = "Default region for regional resources. This week creates none; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

# ---------------------------------------------------------------------------
# The dry-run switch
#
# Every constraint this week adds lands as a dry_run_spec first. A dry-run policy
# is evaluated on every request and logged when it would have denied, but it
# denies nothing — so the violations show up in audit logs before anyone is
# blocked by them.
#
# This is a map rather than one boolean on purpose. A single switch would flip
# the whole set at once, which defeats the point: the sequence being taught is
# land it in dry run, read what it caught, then enforce THAT one. Constraints
# graduate individually, and the map is the record of which have.
#
# Key is the constraint's short name, as used in the resource address below.
# ---------------------------------------------------------------------------
variable "enforce" {
  description = "Per-constraint switch. false = dry_run_spec only (logs, denies nothing). true = enforced. Flip one at a time, after reading its dry-run violations."
  type        = map(bool)
  default     = {}
}

# ---------------------------------------------------------------------------
# Folder lookup, rather than folder IDs in tfvars
#
# Week 01 created workloads/dev and workloads/prod. This week writes a
# deliberate exception at workloads/dev, which needs that folder's numeric ID.
#
# It is resolved by display name at plan time rather than carried in
# terraform.tfvars. A folder ID is not a secret, but it is a value that would
# have to be copied by hand out of one week's output and into another week's
# variables, where it would rot silently the first time the hierarchy is rebuilt.
# The name is the stable thing; the number is not.
# ---------------------------------------------------------------------------
variable "workloads_folder_name" {
  description = "Display name of the top-level workloads folder created in Week 01."
  type        = string
  default     = "workloads"
}

variable "dev_folder_name" {
  description = "Display name of the dev folder inside workloads. The one place this week's exception applies."
  type        = string
  default     = "dev"
}

variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value. Needed because this week creates a project, and a project with no billing account cannot enable compute."
  type        = string
  sensitive   = true
}

variable "host_project_id" {
  description = <<-EOT
    The Shared VPC host project. Week 01 created katta698-gcp-net-hub for exactly
    this and then left it empty: `auto_create_network = false`, so it has never
    had a VPC, not even the permissive default one Google would otherwise make.
  EOT
  type        = string
}

variable "region" {
  description = <<-EOT
    Deliberately us-central1. The Always Free tier covers one non-preemptible
    e2-micro per month in us-west1, us-central1 or us-east1 only — picking any
    other region turns this week from free into billable, and nothing about the
    week needs a different one.
  EOT
  type        = string
  default     = "us-central1"
}

variable "service_project_id" {
  description = "Service project created under workloads/dev and attached to the host. Project IDs are globally unique and permanent, so this carries a suffix to survive a rebuild."
  type        = string
  default     = "katta698-gcp-dev-app-01"
}

# ---------------------------------------------------------------------------
# Subnet ranges
#
# Two subnets rather than one, because a hub with a single spoke does not
# demonstrate the thing Shared VPC is for. The dev and prod ranges are
# non-overlapping and deliberately small — /24 is 256 addresses, of which Google
# reserves four, and nothing in this lab will come close.
#
# RFC 1918 space chosen to not collide with the AWS lab's 10.0.0.0/16, so that
# the two labs could be peered or connected later without renumbering. That
# costs nothing to decide now and is expensive to fix afterwards.
# ---------------------------------------------------------------------------
variable "subnet_dev_cidr" {
  description = "Primary range for the dev subnet."
  type        = string
  default     = "10.20.0.0/24"
}

variable "subnet_prod_cidr" {
  description = "Primary range for the prod subnet. Created now, unused until a prod service project exists — the range is reserved so prod does not later take whatever is free."
  type        = string
  default     = "10.20.1.0/24"
}

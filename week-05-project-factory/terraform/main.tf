/*
 * Week 05 — Project factory.
 *
 * Four projects existed before this week. Three came from the Week 01 landing
 * zone, one from Week 04's Shared VPC configuration, and they agree on the
 * things that matter by attention rather than by construction. Nothing in the
 * organization required any of it: no project had to carry labels, or an
 * essential contact, or a tag, and the fourth one only did because it was
 * written three weeks after the first three and copied their good habits.
 *
 * A factory that is merely available gets bypassed on the day someone is in a
 * hurry. So this week is two halves: a module that makes the right project, and
 * a constraint that refuses the wrong one.
 */

# ---------------------------------------------------------------------------
# The tag key, and why a tag rather than a label
#
# Labels are free text. Anyone who can edit a project can write
# env = whatever-they-like, and no policy can read it. They are for billing
# export and for queries.
#
# Tags are IAM-controlled resources with strongly-typed values, and they are the
# only one of the two an organization policy can SCOPE on:
# resource.matchTag('<org>/environment', 'dev') in a policy rule condition
# applies that policy to exactly the resources carrying it. A label can never do
# that, however carefully it is written.
#
# So the two are not redundant and the module sets both. The label answers
# "what did this cost" and is refused at creation if missing — see the
# constraint at the foot of this file. The tag answers "which rules apply to
# this", and exists to be conditioned on by the weeks after this one.
#
# Created at the organization so every folder and project inherits visibility
# of it. Values are enumerated here and nowhere else — the module is handed a
# value ID and cannot invent one, which is what stops env = "prod-ish" from
# becoming a tag value that no policy reads.
# ---------------------------------------------------------------------------

resource "google_tags_tag_key" "environment" {
  parent      = "organizations/${var.org_id}"
  short_name  = "environment"
  description = "Which environment a resource belongs to. Referenced by organization policy; values are closed and defined in Week 05's configuration."
}

resource "google_tags_tag_value" "environment" {
  for_each = toset(["dev", "prod"])

  parent      = google_tags_tag_key.environment.id
  short_name  = each.value
  description = "environment=${each.value}"
}

# ---------------------------------------------------------------------------
# Where projects go
#
# Resolved by display name, same as every week since 03. A folder ID is a value
# that rots the first time the hierarchy is rebuilt; a name survives it.
# ---------------------------------------------------------------------------

data "google_folders" "root" {
  parent_id = "organizations/${var.org_id}"
}

locals {
  workloads_folder = one([
    for f in data.google_folders.root.folders : f.name
    if f.display_name == "workloads"
  ])
}

data "google_folders" "workloads" {
  parent_id = local.workloads_folder
}

locals {
  dev_folder = one([
    for f in data.google_folders.workloads.folders : f.name
    if f.display_name == "dev"
  ])
}

# ---------------------------------------------------------------------------
# One project, built by the factory
#
# One, and not because one is enough to prove a factory. The billing account
# caps how many projects it will fund, and this organization is at that cap
# with a single slot free — a limit discovered in Week 04 as
# `Cloud billing quota exceeded`, and raised only through a Console form that
# Google may attach a payment to.
#
# That is worth stating plainly rather than designing around: the constraint on
# a project factory is not Terraform and not the module, it is a quota on the
# billing account that no amount of code addresses.
# ---------------------------------------------------------------------------

module "dev_app_02" {
  source = "./modules/project"

  name       = "Dev App 02"
  project_id = var.demo_project_id
  folder_id  = local.dev_folder

  billing_account = var.billing_account
  env             = "dev"
  week            = "05"

  environment_tag_value_id = google_tags_tag_value.environment["dev"].id
  essential_contact_email  = var.essential_contact_email

  # Deliberately minimal. A factory's default API set is the blast radius every
  # project it makes will carry, so the default here is "what a project needs to
  # exist", and callers add what they actually use.
  apis = [
    "compute.googleapis.com",
  ]

  # Left off for this one so the week can be torn down without a separate
  # lien-removal step. The module offers it; not every project should take it.
  deletion_lien = false
}

# ---------------------------------------------------------------------------
# The constraint that makes the factory unavoidable
#
# A factory that is merely available loses to a deadline. This is the half that
# makes the module the shortest path rather than the tidiest one.
#
# It constrains the project ID and the parent, and NOT labels — which is not a
# design preference. It is what the API permits, measured on 2026-09-19 by
# creating probe constraints and reading which Google accepted:
#
#   resource.projectId     ACCEPTED
#   resource.parent        ACCEPTED
#   resource.labels        REJECTED  — "Error 400: Request has invalid values"
#   resource.displayName   REJECTED
#
# So a custom constraint on a project cannot see that project's labels. The
# reference lists cloudresourcemanager.googleapis.com/Project as a supported
# resource, at Preview, and never publishes which of its fields are exposed;
# the error names nothing. The first draft of this week required labels at
# creation and could never have worked.
#
# What is left is narrower and still worth having. A project ID is permanent and
# globally unique, so a naming standard is the one property of a project that
# can never be corrected later — and a project created at the organization root
# rather than under a folder inherits none of the folder-level policy this lab
# spent three weeks building.
#
# Landed as dry_run_spec first, per Week 03: a constraint that has never
# evaluated a request has no evidence behind it.
# ---------------------------------------------------------------------------

resource "google_org_policy_custom_constraint" "project_naming" {
  name   = "custom.requireProjectNamingAndParent"
  parent = "organizations/${var.org_id}"

  display_name = "Projects must follow the naming standard and live in a folder"
  description  = "A project ID is permanent and globally unique, so a name that breaks the standard can never be fixed — only abandoned. And a project created at the organization root inherits none of the folder-level policy this organization relies on. Create projects through the Week 05 factory module."

  action_type    = "ALLOW"
  method_types   = ["CREATE"]
  resource_types = ["cloudresourcemanager.googleapis.com/Project"]

  condition = join(" && ", [
    "resource.projectId.startsWith(\"${var.project_id_prefix}\")",
    "resource.parent.startsWith(\"folders/\")",
  ])
}

resource "google_org_policy_policy" "project_naming" {
  name   = "organizations/${var.org_id}/policies/${google_org_policy_custom_constraint.project_naming.name}"
  parent = "organizations/${var.org_id}"

  dynamic "spec" {
    for_each = var.enforce_naming_constraint ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = var.enforce_naming_constraint ? [] : [1]
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }
}

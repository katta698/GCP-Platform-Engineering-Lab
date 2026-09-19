/*
 * The project module.
 *
 * Four projects existed before this week, each created a slightly different
 * way: three by the Week 01 landing zone, one by Week 04's Shared VPC config.
 * They agree on the important things by luck and attention rather than by
 * construction, which is exactly the point at which a factory starts earning
 * its place — not when project creation is hard, but when it is easy enough
 * that four people do it four ways.
 *
 * What this module refuses to make optional is the interesting part. A factory
 * whose every control has a toggle is a factory that produces whatever the
 * caller asked for, which is what it was meant to replace.
 */

# ---------------------------------------------------------------------------
# The project
# ---------------------------------------------------------------------------

resource "google_project" "this" {
  name       = var.name
  project_id = var.project_id
  folder_id  = var.folder_id

  billing_account = var.billing_account

  # Not a parameter, and deliberately so. Google's default network is a
  # full auto-mode VPC in every region with permissive firewall rules that
  # nobody asked for. A factory that lets a caller opt back into it is a
  # factory that will be asked to, on the day someone is in a hurry.
  auto_create_network = false

  # Labels are free text, queryable, and land in the billing export. Tags —
  # below — are IAM-controlled and are the only one of the two that can
  # condition an organization policy. The module sets both because they answer
  # different questions: labels answer "what did this cost", tags answer
  # "may this be created at all".
  labels = {
    week       = var.week
    env        = var.env
    managed-by = "terraform"
  }

  # Provider 6.x defaults this to PREVENT, which surfaced in Week 04 as
  # "Cannot destroy project as deletion_policy is set to PREVENT" on a tainted
  # project that then could not be replaced. Stated explicitly here rather than
  # inherited, so the behaviour is visible to whoever reads the module rather
  # than discovered during an apply that is already failing.
  deletion_policy = "PREVENT"
}

# ---------------------------------------------------------------------------
# APIs
#
# One resource per API, never a generous default. There is no way to ask Google
# Cloud for "the usual set", and every enabled API is surface that the project
# did not have to have.
#
# disable_on_destroy = false throughout: disabling an API that another project's
# resources depend on is a far worse failure than leaving one enabled, and an
# enabled API costs nothing on its own.
# ---------------------------------------------------------------------------

resource "google_project_service" "this" {
  for_each = toset(var.apis)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# The environment tag
#
# The value is passed in, never constructed here. If the module could build a
# tag value from a string, then a caller passing env = "prod-ish" would create
# a tag value that no policy conditions on, and the project would look tagged
# while being outside every rule that reads the tag. The caller owns the key
# and its permitted values; the module may only bind one that already exists.
#
# Bound to the project by its NUMBER, not its ID. Tag bindings address the
# resource through the Resource Manager's own naming, and a project's number is
# the stable identifier there.
# ---------------------------------------------------------------------------

resource "google_tags_tag_binding" "environment" {
  parent    = "//cloudresourcemanager.googleapis.com/projects/${google_project.this.number}"
  tag_value = var.environment_tag_value_id
}

# ---------------------------------------------------------------------------
# Essential contacts
#
# Google sends operational notices — security bulletins, deprecation warnings,
# suspension notices — to Essential Contacts, and to nobody else. A project
# with none is a project where the notice that a credential leaked goes to an
# address that does not exist.
#
# This is the control most obviously worth centralising in a factory: it is
# easy, it is invisible when missing, and nothing breaks until the one day it
# matters.
# ---------------------------------------------------------------------------

resource "google_essential_contacts_contact" "this" {
  parent                              = "projects/${google_project.this.project_id}"
  email                               = var.essential_contact_email
  language_tag                        = "en"
  notification_category_subscriptions = var.essential_contact_categories

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Optional deletion lien
#
# Optional because most projects should be deletable — a lab that cannot tear
# down its own work accumulates cost and confusion. It is offered at all
# because a lien is the only control that refuses deletion regardless of who
# asks: an organization administrator holding every role is refused exactly
# like anyone else until the lien is deliberately removed.
#
# Both fields are shown to whoever hits the refusal, so they are written for
# that person rather than as a change-log entry.
# ---------------------------------------------------------------------------

resource "google_resource_manager_lien" "this" {
  count = var.deletion_lien ? 1 : 0

  parent       = "projects/${google_project.this.project_id}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "week-05-project-factory"
  reason       = "Created by the project factory with deletion protection requested. Remove this lien deliberately before deleting the project."
}

/*
 * Week 10 — Group-based access.
 *
 * Nine weeks of this lab granted roles to individuals. Measured before writing
 * any of this, against the live organization rather than against the config:
 *
 *   gcloud organizations get-iam-policy <ORG> \
 *     --flatten="bindings[].members" --filter="bindings.members~^group:"
 *   -> no rows
 *
 *   gcloud identity groups search --organization=<ORG> \
 *     --labels=cloudidentity.googleapis.com/groups.discussion_forum \
 *     --billing-project=<SEED>
 *   -> no rows
 *
 * Zero group bindings, and zero groups. Every grant so far names a person or a
 * service account, which means every change of responsibility is a change to an
 * IAM policy, and the policy is where you find out who can do what.
 *
 * Google's guidance is the one-liner version: "Instead of granting roles to
 * individual principals, you grant roles to the group, and then manage group
 * membership."
 *
 * The week proves that indirection actually works, which means proving access
 * APPEARS and DISAPPEARS with membership and nothing else.
 */

# ---------------------------------------------------------------------------
# The API
#
# Explicit resource per CLAUDE.md, disable_on_destroy = false so tearing this
# week down does not break anything else that later turns out to need it.
# ---------------------------------------------------------------------------

resource "google_project_service" "cloudidentity" {
  project            = var.seed_project_id
  service            = "cloudidentity.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# The test subject
#
# The revocation test is worthless run as a principal that holds the permission
# by another path, and in this organization the obvious human holds
# roles/resourcemanager.organizationAdmin plus super admin — nothing can be
# denied to them by removing a group membership, so a passing test would prove
# only that the test was wrong. Week 02 learned the same lesson pointing the
# other way: an under-privileged attempt fails for the wrong reason.
#
# So the subject is a service account created for this and granted nothing
# directly. Group membership is its ONLY route to the permission, which is what
# makes the before/after meaningful.
# ---------------------------------------------------------------------------

resource "google_service_account" "group_demo" {
  project      = var.seed_project_id
  account_id   = "group-access-demo"
  display_name = "Week 10 - holds nothing; gets logging.viewer only via a group"
  description  = "Test subject for group-based access. Any direct role binding on this account invalidates the week's measurement."
}

# The operator needs to be able to mint a token as the subject to run the test
# at all. Scoped to this one service account - not the project, not the folder.
resource "google_service_account_iam_member" "operator_can_impersonate" {
  service_account_id = google_service_account.group_demo.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.operator_principal}"
}

# ---------------------------------------------------------------------------
# The group
#
# An ACCESS group in Google's taxonomy: it exists to carry permissions, is named
# for the access it grants rather than for a team, and is deliberately not
# nested. Google's own best-practice page splits groups four ways and gives them
# different rules — organizational groups SHOULD mirror the org chart and may be
# nested, access groups typically should NOT be nested because nesting makes it
# hard to answer who has access, enforcement groups must not be nested, and
# collaboration groups should never be used for access control at all.
#
# `labels` here is not the week/env/managed-by convention every other resource
# in this lab carries — Cloud Identity uses the field to declare what KIND of
# group this is, and the discussion_forum label is what makes it a Google Group
# rather than something else. There is no free-form label surface to tag.
# ---------------------------------------------------------------------------

resource "google_cloud_identity_group" "log_readers" {
  display_name = "GCP log readers (Week 10)"
  description  = "Access group. Members can read logs in the platform folder. Managed by Terraform; do not add members by hand."

  # Groups hang off the CUSTOMER, not the organization. Every other resource in
  # this lab is parented to organizations/, folders/ or projects/; this one is
  # not, and a parent of organizations/<id> is rejected.
  parent = "customers/${var.customer_id}"

  group_key {
    id = "grp-gcp-log-readers@${var.domain}"
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  # The least-privilege path, and the reason this week grants the pipeline NO
  # Workspace admin role.
  #
  # Creating a group with initial_group_config = EMPTY requires the caller to be
  # a Super Admin or a Groups Admin, and Groups Admin is all-or-nothing: it can
  # manage every group in the Cloud Identity account, including ones it did not
  # create. Granting that to a CI identity to let it manage three groups is the
  # same mistake as granting Editor to let something write one bucket.
  #
  # WITH_INITIAL_OWNER instead makes the CALLER the owner of the group it just
  # created. Google's own guidance for an IaC pipeline: give it the ability to
  # create a group and let it own what it creates, "which lets that pipeline
  # manage any group it creates and create more groups without authorizing it to
  # manage any group it did not create."
  #
  # Whether this works without an admin role depends on the domain's group
  # creation setting, which defaults to permitting it. Tested rather than
  # assumed - see docs/references.md for what the apply actually returned.
  initial_group_config = "WITH_INITIAL_OWNER"

  depends_on = [google_project_service.cloudidentity]
}

resource "google_cloud_identity_group_membership" "demo_sa" {
  group = google_cloud_identity_group.log_readers.id

  preferred_member_key {
    id = google_service_account.group_demo.email
  }

  # MEMBER, not MANAGER or OWNER. The subject should be able to use the access
  # the group carries and should not be able to change who else gets it.
  roles {
    name = "MEMBER"
  }
}

# ---------------------------------------------------------------------------
# The grant
#
# One binding, to the group, at the folder. This is the whole point of the week:
# after this, changing who can read logs is a membership change, not a policy
# change.
#
# _member and never _binding. google_folder_iam_binding is AUTHORITATIVE for the
# role — it replaces the full member list, so applying it would silently remove
# anyone else holding roles/logging.viewer on this folder and Terraform would
# report it as a successful one-line change. _member is additive and touches
# only the principal it names.
# ---------------------------------------------------------------------------

resource "google_folder_iam_member" "log_readers_can_read" {
  folder = var.platform_folder_id
  role   = "roles/logging.viewer"
  member = "group:${google_cloud_identity_group.log_readers.group_key[0].id}"
}

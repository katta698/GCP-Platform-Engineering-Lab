/*
 * Week 11 — Just-in-time privileged access.
 *
 * Ten weeks of this lab granted roles that stay granted. Measured before
 * writing any of this, against the live organization:
 *
 *   gcloud services list --project=<SEED> | grep privilegedaccess
 *   -> not enabled
 *
 *   gcloud pam entitlements list --organization=<ORG> --location=global
 *   -> PERMISSION_DENIED
 *
 * No entitlements, and the API off. Every role in the estate is permanent: once
 * granted it stays until somebody writes a change to remove it, and nobody is
 * scheduled to. That is fine for a pipeline identity whose job never changes,
 * and wrong for the access a person needs twice a year.
 *
 * Privileged Access Manager inverts it. An ENTITLEMENT describes access that
 * MAY be requested - who is eligible, which roles, for how long, and who must
 * approve. It is a template, not a binding: until someone requests a grant
 * against it, the folder's IAM policy is unchanged. When a grant is approved
 * the binding appears, and when the grant expires PAM removes it.
 *
 * The week's claim is that last clause, so the week has to prove it: the same
 * command, as the same principal, refused -> permitted -> refused, across a
 * timer nobody touched. And it owes a number for how long the removal takes,
 * because "access ended" is false for however long that lag is.
 *
 * What this week deliberately does NOT claim: that anything in this estate
 * needed temporary access. Finding over-permissioned principals is the IAM
 * recommender's job, and role recommendations for non-basic roles sit behind
 * Security Command Center Premium. Every grant here is a predefined role, so
 * the free tier would report nothing. This is the mechanism, demonstrated; it
 * is not evidence that the mechanism was warranted.
 */

# ---------------------------------------------------------------------------
# The API
#
# Explicit resource per CLAUDE.md, disable_on_destroy = false so tearing this
# week down does not disable an API something later turns out to need.
# ---------------------------------------------------------------------------

resource "google_project_service" "pam" {
  project            = var.seed_project_id
  service            = "privilegedaccessmanager.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# The requester
#
# The subject has to be a principal that genuinely lacks the role, or the
# before/after proves nothing. The obvious human holds organizationAdmin and
# Cloud Identity super admin, so no entitlement can make them MORE able to read
# an IAM policy and no expiry can make them less - a passing test would only
# prove the test was wrong. Week 02 learned the same lesson from the other
# direction: an under-privileged attempt fails for the wrong reason and looks
# identical to the control working.
#
# So the requester is a service account created for this and granted nothing
# directly. The entitlement is its only route to the role.
# ---------------------------------------------------------------------------

resource "google_service_account" "jit_subject" {
  project      = var.seed_project_id
  account_id   = "jit-access-demo"
  display_name = "Week 11 - holds nothing; gets a role only through a PAM grant"
  description  = "Test subject for just-in-time access. Any direct role binding on this account invalidates the week's measurement."
}

# The operator mints a token as the subject to make the request at all. Scoped
# to this one service account - not the project, not the folder.
resource "google_service_account_iam_member" "operator_can_impersonate" {
  service_account_id = google_service_account.jit_subject.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.operator_principal}"
}

# ---------------------------------------------------------------------------
# The entitlement
#
# Read this as four separate decisions rather than one block:
#
#   parent                - where the access applies, and the widest thing the
#                           pipeline is able to write (see variables.tf)
#   eligible_users        - who may ASK. Not who has access.
#   approval_workflow     - who must say yes. Different principal from the
#                           requester, or the step is theatre.
#   max_request_duration  - the ceiling. A requester may ask for less and never
#                           for more.
#
# Nothing here grants anything. That is the point of the resource, and the
# reason figure 03 is worth taking: an entitlement exists and the folder's IAM
# policy is untouched.
# ---------------------------------------------------------------------------

resource "google_privileged_access_manager_entitlement" "folder_security_review" {
  entitlement_id = "folder-security-review"
  location       = "global"
  parent         = "folders/${var.platform_folder_id}"

  max_request_duration = var.max_request_duration

  eligible_users {
    principals = ["serviceAccount:${google_service_account.jit_subject.email}"]
  }

  privileged_access {
    gcp_iam_access {
      resource      = "//cloudresourcemanager.googleapis.com/folders/${var.platform_folder_id}"
      resource_type = "cloudresourcemanager.googleapis.com/Folder"

      role_bindings {
        role = var.elevated_role
      }
    }
  }

  # A free-text reason, required on every request. It is the only part of the
  # audit trail that records WHY rather than what, and it costs the requester
  # one sentence. not_mandatory is the alternative and is the wrong default for
  # anything privileged.
  requester_justification_config {
    unstructured {}
  }

  approval_workflow {
    manual_approvals {
      require_approver_justification = true

      steps {
        approvals_needed = 1

        approvers {
          principals = ["user:${var.operator_principal}"]
        }
      }
    }
  }

  depends_on = [google_project_service.pam]
}

/*
 * Week 08 — Least privilege, and the guardrail that keeps it.
 *
 * Week 07 left a hole and wrote it down: tf-plan, the READ-ONLY identity, holds
 * roles/cloudasset.owner, because no predefined role carries cloudasset.feeds.get
 * without also carrying create, update and delete. Policy Troubleshooter agrees:
 *
 *   principal:  tf-plan@...
 *   permission: cloudasset.feeds.delete
 *   access:     GRANTED
 *
 * Two fixes, and the order matters. The custom role is the FIX — it removes the
 * permission at source. The deny policy is the GUARDRAIL — it survives someone
 * re-granting owner next quarter. Shipping only the guardrail would leave an
 * identity holding owner and call it safe, which is the thing to avoid.
 */

resource "google_project_service" "iam_api" {
  for_each = toset([
    "iam.googleapis.com",
    "policytroubleshooter.googleapis.com", # how the before/after is measured
  ])

  project            = var.seed_project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# THE FIX — a role carrying exactly what a plan needs
#
# Two permissions. A `terraform plan` that refreshes an asset feed reads it and
# nothing else; everything beyond get/list in roles/cloudasset.owner was a
# side-effect of there being no smaller predefined role.
#
# The trade-off, stated rather than hidden: a custom role does not track Google.
# When a new permission becomes necessary to read a feed, a predefined role picks
# it up automatically and this one does not — it fails a plan until someone adds
# it. That maintenance is the price of least privilege here, and it is a real
# price, not a rhetorical one.
# ---------------------------------------------------------------------------

resource "google_organization_iam_custom_role" "plan_asset_reader" {
  org_id      = var.org_id
  role_id     = "tfPlanAssetReader"
  title       = "Terraform Plan - Asset Reader"
  description = "Read asset feeds during a plan. Replaces roles/cloudasset.owner on the read-only CI identity (Week 08)."

  permissions = [
    "cloudasset.feeds.get",
    "cloudasset.feeds.list",
  ]
}

# The binding for tf-plan is NOT here. An identity must not manage its own
# grants, so swapping tf-plan from cloudasset.owner to this role happens in
# week-02-keyless-ci, hand-applied — the same rule every week has followed.

# ---------------------------------------------------------------------------
# THE GUARDRAIL — deny the delete to everyone who should never do it
#
# Scoped deliberately wider than tf-plan. Denying only the identity we just
# fixed would protect against the problem we already solved and nothing else.
# The useful guardrail is "nobody deletes an asset feed", with two exceptions:
#
#   tf-apply        because Terraform legitimately manages the feed's lifecycle
#   break-glass     because a deny with no way out gets deleted under pressure,
#                   and deleting the policy removes the control completely
#
# Deny beats allow: this refuses the permission no matter what role anyone holds,
# including Organization Admin. That is the point, and it is also why the
# exception list is not optional.
# ---------------------------------------------------------------------------

resource "google_iam_deny_policy" "no_feed_deletion" {
  parent       = urlencode("cloudresourcemanager.googleapis.com/organizations/${var.org_id}")
  name         = "deny-asset-feed-deletion"
  display_name = "Week 08 - no one deletes an asset feed by hand"

  rules {
    deny_rule {
      denied_principals = ["principalSet://goog/public:all"]

      # Deny policies use IAM v2 principal identifiers, which are NOT the
      # member strings used everywhere else in Terraform. A service account is
      # principal://iam.googleapis.com/projects/-/serviceAccounts/<email>, a
      # human is principal://goog/subject/<email>, and only "everyone" takes the
      # principalSet:// form. Using the allow-policy spelling fails with
      # "invalid principal ... as part of the exempted principals list".
      exception_principals = [
        "principal://iam.googleapis.com/projects/-/serviceAccounts/${var.apply_service_account}",
        "principal://goog/subject/${var.break_glass_principal}",
      ]

      denied_permissions = [
        "cloudasset.googleapis.com/feeds.delete",
      ]
    }
  }

  depends_on = [google_project_service.iam_api]
}

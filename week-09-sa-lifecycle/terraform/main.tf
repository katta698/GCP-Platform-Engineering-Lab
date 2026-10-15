/*
 * Week 09 — Service account hygiene.
 *
 * Week 02 built the mechanism: who may become whom, keylessly, with short-lived
 * tokens. This week asks a different question about the same objects — which of
 * these identities should still exist at all.
 *
 * Measured before writing any of this, with Activity Analyzer:
 *
 *   finops-reader@…        last authenticated 2026-10-09
 *   tf-plan@…              last authenticated 2026-10-05
 *   tf-apply@…             last authenticated 2026-10-05
 *   398884169348-compute@  NEVER AUTHENTICATED
 *   851623897121-compute@  NEVER AUTHENTICATED
 *
 * The last two are default Compute Engine service accounts. Nobody created
 * them, nobody has ever used them, and they hold no role anywhere — this
 * organization's baseline already disables the automatic Editor grant that
 * normally makes them dangerous. What remains is two credentials that exist for
 * no reason, which is a smaller problem than the usual one and still a problem.
 */

# ---------------------------------------------------------------------------
# Disable, never delete
#
# Google's own guidance: disable first, confirm nothing breaks, and only then
# consider deleting. Deleting is the irreversible half, and not for the reason
# people assume — the email CAN be reused, but IAM tracks an internal unique ID,
# so role bindings that referred to the deleted account never apply to a
# recreated one with the same address. A rebuild looks identical and is not.
#
# DISABLE is reversible in one field, which is the whole argument for it.
# ---------------------------------------------------------------------------

resource "google_project_default_service_accounts" "logging" {
  project = var.logging_project_id
  action  = "DISABLE"

  # Restore the accounts to their prior state if this resource is destroyed,
  # so tearing the week down does not silently leave them disabled.
  restore_policy = "REVERT"
}

resource "google_project_default_service_accounts" "security" {
  project = var.security_project_id
  action  = "DISABLE"

  restore_policy = "REVERT"
}

# ---------------------------------------------------------------------------
# Close the generation gap on key creation
#
# This lab's first rule is "no service account keys, ever", and the organization
# does enforce it — on the MANAGED generation,
# constraints/iam.managed.disableServiceAccountKeyCreation.
#
# The legacy constraint of the same name has no policy at all and therefore
# evaluates to enforce:false. Reading that one and stopping produces a confident,
# wrong conclusion that the rule is unenforced. That happened while planning this
# week, and the only thing that prevented a false alarm was checking the other
# generation.
#
# So: set the legacy one too. It is redundant while the baseline holds, which is
# exactly what defence in depth means, and it removes a trap for whoever checks
# next. Week 03 deliberately left the baseline alone and still does — this adds a
# policy on a constraint that had none, rather than editing Google's.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "no_sa_key_creation_legacy" {
  name   = "organizations/${var.org_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

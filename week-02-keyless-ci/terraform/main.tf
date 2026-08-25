/*
 * Week 02 — Keyless CI.
 *
 * The usual Google Cloud CI failure — a service account key in a file or a CI
 * variable — is already impossible in this organization, and nobody here decided
 * that. Every organization created on or after 3 May 2024 inherits Google's
 * security baseline, and this one arrived with disableServiceAccountKeyCreation
 * and disableServiceAccountKeyUpload already enforced.
 *
 * So this week does not ban the shortcut. It builds the only path the platform
 * left open: HCP Terraform mints an OIDC token per run, Google's Security Token
 * Service exchanges it for a federated token, and that token impersonates a
 * service account for the length of the run. Nothing is ever written to disk,
 * and there is no key to leak because there is no key.
 */

# ---------------------------------------------------------------------------
# APIs
#
# sts is the exchange endpoint, iamcredentials mints the impersonated token, iam
# owns the pool itself. Each is a distinct call in one run, and missing any of
# the three fails in a different place.
# ---------------------------------------------------------------------------

resource "google_project_service" "wif" {
  for_each = toset([
    "iam.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project = var.seed_project_id
  service = each.value

  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# The pool and its provider
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "hcp" {
  project                   = var.seed_project_id
  workload_identity_pool_id = "hcp-terraform"
  display_name              = "HCP Terraform"
  description               = "Federated identity for Terraform runs. Created Week 02."

  depends_on = [google_project_service.wif]
}

resource "google_iam_workload_identity_pool_provider" "hcp" {
  project                            = var.seed_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.hcp.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform-oidc"
  display_name                       = "HCP Terraform OIDC"

  oidc {
    issuer_uri = "https://app.terraform.io"
  }

  # No allowed_audiences. Left unset, Google accepts its own default audience —
  # the provider's full resource name — which is exactly what HCP sends unless
  # TFC_GCP_WORKLOAD_IDENTITY_AUDIENCE overrides it. Setting it by hand here
  # would only create a second place for the two ends to disagree.

  attribute_mapping = {
    "google.subject"                        = "assertion.sub"
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name"
    "attribute.terraform_project_name"      = "assertion.terraform_project_name"
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name"
    "attribute.terraform_run_phase"         = "assertion.terraform_run_phase"
  }

  # The single most important expression in this week.
  #
  # https://app.terraform.io is a PUBLIC issuer. Every HCP Terraform user on
  # earth holds a validly signed token from it. Without this condition, the only
  # thing standing between any of them and this organization is that they have
  # not guessed the provider's resource name — which is not a secret, and is
  # printed in plan output.
  #
  # Three claims, narrowing in turn: the HCP organization, the project inside it,
  # and the workspace naming prefix. The AWS lab's workspaces live in the same
  # HCP organization and carry tokens from the same issuer; the project and
  # prefix checks are what keep them out.
  attribute_condition = join(" && ", [
    "assertion.terraform_organization_name == \"${var.hcp_organization}\"",
    "assertion.terraform_project_name == \"${var.hcp_project_name}\"",
    "assertion.terraform_workspace_name.startsWith(\"${var.workspace_prefix}\")",
  ])
}

# ---------------------------------------------------------------------------
# Two service accounts, split by run phase
#
# HCP names the plan and apply identities separately
# (TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL / TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL), and
# the token carries a terraform_run_phase claim saying which one is running. So
# the split is enforced by Google at token exchange, not by convention: a
# speculative plan on a pull request cannot mutate anything, because the identity
# it is able to assume holds no role that can.
# ---------------------------------------------------------------------------

resource "google_service_account" "plan" {
  project      = var.seed_project_id
  account_id   = "tf-plan"
  display_name = "Terraform plan (read-only)"
  description  = "Assumed by HCP Terraform during the plan phase. Holds read roles only."

  depends_on = [google_project_service.wif]
}

resource "google_service_account" "apply" {
  project      = var.seed_project_id
  account_id   = "tf-apply"
  display_name = "Terraform apply"
  description  = "Assumed by HCP Terraform during the apply phase."

  depends_on = [google_project_service.wif]
}

# Who may impersonate which. The principalSet is scoped to the run phase
# attribute, so an apply-phase token cannot assume the plan account or the
# reverse — the binding simply does not match.
#
# These two bindings are the ones at risk from the baseline's domain-restricted
# sharing constraint (iam.allowedPolicyMemberDomains), which applies to
# principalSet:// members and not only to users and groups. If an apply fails
# here, that is why; see the README.
resource "google_service_account_iam_member" "plan_federation" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp.name}/attribute.terraform_run_phase/plan"
}

resource "google_service_account_iam_member" "apply_federation" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp.name}/attribute.terraform_run_phase/apply"
}

# ---------------------------------------------------------------------------
# What each identity may do
#
# Granted at the organization because that is the narrowest scope that works:
# folders and projects are created as children of the org, so a folder-scoped
# grant cannot create the folder it would be scoped to.
# ---------------------------------------------------------------------------

# Read-only, and narrow.
#
# roles/viewer was here first, on the reasoning that a plan only reads, so
# breadth costs nothing. That reasoning is wrong. roles/viewer confers
# storage.legacyObjectReader on every bucket, which makes this not "read the
# hierarchy" but "read every object in every project in the organization,
# including projects that do not exist yet" — reachable by any HCP workspace that
# satisfies the attribute condition above. Google's guidance is not to grant
# basic roles in production at all; they carry thousands of permissions across
# every service.
#   https://docs.cloud.google.com/storage/docs/access-control/iam-roles
#   https://docs.cloud.google.com/iam/docs/choose-predefined-roles
#
# roles/browser stays, and the note that earned it stays with it: roles/viewer
# does not include resourcemanager.folders.get. Basic roles predate the resource
# hierarchy and describe a project's contents, not the structure a project hangs
# from — so an organization-level grant of viewer inherits downward and still
# cannot read a folder. Measured, not assumed: a remote plan of Week 01 failed on
# exactly that permission.
#
# The rest is what a refresh of this lab's resources actually reads. If a later
# week's plan needs more, add that one role and say which resource needed it.
# Do not reach back for roles/viewer.
resource "google_organization_iam_member" "plan" {
  for_each = toset([
    "roles/browser",                         # folders, projects, the tree itself
    "roles/orgpolicy.policyViewer",          # org policy, Week 03 onward
    "roles/serviceusage.serviceUsageViewer", # google_project_service
    "roles/iam.securityReviewer",            # IAM policies, for drift in bindings
    "roles/iam.workloadIdentityPoolViewer",  # this week's own pool and provider
  ])

  org_id = var.org_id
  role   = each.value
  member = google_service_account.plan.member
}

resource "google_organization_iam_member" "apply" {
  for_each = toset([
    # Week 01's hierarchy, and every folder a later week adds.
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.projectDeleter",
    # Every project this lab builds enables its own APIs explicitly.
    "roles/serviceusage.serviceUsageAdmin",
    # Later weeks create their own workload service accounts.
    "roles/iam.serviceAccountAdmin",
    # Week 03 writes organization policy. Granted here so that week does not
    # need a second hand-run apply to grant its own permissions.
    "roles/orgpolicy.policyAdmin",
  ])

  org_id = var.org_id
  role   = each.value
  member = google_service_account.apply.member
}

# ---------------------------------------------------------------------------
# What is deliberately NOT here: the billing account
#
# tf-apply needs roles/billing.user to attach a new project to billing, and the
# billing account sits outside the resource hierarchy, so no organization grant
# reaches it. The obvious move is a google_billing_account_iam_member here. It
# was written, applied, and removed, for two reasons.
#
# The first is mechanical. Managing that binding in this configuration means
# every future run refreshes it, so tf-apply would permanently need
# billing.accounts.getIamPolicy just to plan. Read access to billing IAM, on
# every run, forever, to manage one line.
#
# The second is the real one. That would make tf-apply the manager of roles on
# the billing account it spends against — an identity able to widen its own
# access to money. The separation is worth more than the automation: the grant is
# made once, by a human, out of band, and the CI identity can spend but can never
# change who may spend.
#
# Recorded in the README as a prerequisite. It also cannot be done by the
# organization's own admin: this billing account is owned by the personal
# identity that created it, and granting on it needs roles/billing.admin, which
# katta698@ deliberately does not hold — it has costsManager, which covers
# budgets and nothing else.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# A lien on the seed project
#
# tf-apply holds roles/resourcemanager.projectDeleter at the organization, which
# includes the seed project — the one holding this pool, this provider, and both
# identities. An apply that deletes it takes the lab's entire authentication
# layer with it, and there is nothing left to authenticate the repair.
#
# The bootstrap already sets prevent_destroy on that project, and that is worth
# having, but it is a Terraform-side guard: it refuses a destroy in that one
# configuration. It says nothing to a gcloud call, a console click, or a
# different configuration running as tf-apply. The guard lives in the state file,
# and the risk lives in the cloud.
#
# A lien is the same idea enforced by Google rather than by Terraform. Deletion
# is refused at the API, whoever asks and however they ask, until the lien is
# removed — which is itself a deliberate act requiring
# resourcemanager.projects.updateLiens.
#
# It belongs in this week rather than the bootstrap because the thing it defends
# against is the identity this week creates.
# ---------------------------------------------------------------------------

resource "google_resource_manager_lien" "seed" {
  parent       = "projects/${var.seed_project_id}"
  restrictions = ["resourcemanager.projects.delete"]

  # Both fields are shown to whoever hits the refusal, so they are written for
  # that person rather than for a change log.
  origin = "week-02-keyless-ci"
  reason = "Holds the workload identity pool and the CI service accounts. Deleting it removes the lab's ability to authenticate anything, including the repair."
}

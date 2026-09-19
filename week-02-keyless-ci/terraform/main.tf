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

# ---------------------------------------------------------------------------
# Compute, added for Week 04 — and why it is added HERE
#
# Week 04 builds a Shared VPC. tf-apply could not do any of it: the six roles
# above cover folders, projects, service usage, service accounts and org policy,
# and not one compute permission among them. Four things were missing — create
# the network, enable Shared VPC hosting, write a hierarchical firewall policy,
# and create an instance.
#
# The obvious fix is to grant those in Week 04's own configuration, next to the
# resources that need them. That is the one thing this lab will not do, and the
# reason is the same one that keeps this workspace on local execution and that
# removed the billing binding from it: **an identity must not manage its own
# grants.** A configuration applied by tf-apply that also widens tf-apply is a
# configuration where the CI identity can give itself anything it later decides
# it wants, and no reviewer sees a difference between that and a legitimate
# feature.
#
# So the grants live in the human-run layer, applied from a person's
# credentials, and Week 04 consumes them. This is the two-layer split working,
# not an inconvenience around it. It also means every widening of CI is a
# deliberate, separately-reviewed act rather than a line buried in a week that
# happens to need it.
#
# Scope: folder where a folder will do, organization only where the API gives no
# choice. Stated per role below rather than in one sweeping grant.
# ---------------------------------------------------------------------------

data "google_folders" "root" {
  parent_id = "organizations/${var.org_id}"
}

locals {
  platform_folder = one([
    for f in data.google_folders.root.folders : f.name
    if f.display_name == "platform"
  ])
  workloads_folder = one([
    for f in data.google_folders.root.folders : f.name
    if f.display_name == "workloads"
  ])
}

# The network itself lives in the network hub project, which sits under
# platform. Scoping here rather than at the organization means a compromised or
# mistaken CI run cannot rewrite networking in projects this lab does not own —
# including projects that do not exist yet, which is the reach that made
# roles/viewer unacceptable for the plan identity.
resource "google_folder_iam_member" "apply_network_admin" {
  folder = local.platform_folder
  role   = "roles/compute.networkAdmin"
  member = google_service_account.apply.member
}

# Instances are created in service projects under workloads, never in platform.
# The split is the point of the Week 01 hierarchy: the thing that runs workloads
# and the thing that runs the platform are different blast radii.
resource "google_folder_iam_member" "apply_instance_admin" {
  folder = local.workloads_folder
  role   = "roles/compute.instanceAdmin.v1"
  member = google_service_account.apply.member
}

# Service projects are created under workloads and attached to the host project
# under platform, so the attaching identity needs to be able to act on both.
resource "google_folder_iam_member" "apply_workloads_network_admin" {
  folder = local.workloads_folder
  role   = "roles/compute.networkAdmin"
  member = google_service_account.apply.member
}

# roles/compute.xpnAdmin CANNOT be narrowed the way the three above were, and
# that is worth stating rather than glossing. Enabling a project as a Shared VPC
# host, and attaching service projects to it, are organization-level operations;
# Google defines the role at the organization or folder and the host-enablement
# call is checked at the organization. Granting it at a folder does not work for
# the enablement step.
#
# So this one grant is genuinely org-wide, and it is the widest permission this
# lab has given CI. It permits designating any project in the organization as a
# Shared VPC host and attaching any project to it. It does not permit creating
# or changing the networks themselves — that is networkAdmin, scoped above.
resource "google_organization_iam_member" "apply_xpn_admin" {
  org_id = var.org_id
  role   = "roles/compute.xpnAdmin"
  member = google_service_account.apply.member
}

# Hierarchical firewall policies attach to organization and folder nodes, so the
# role that administers them is defined at the organization. Same shape as
# orgpolicy.policyAdmin, which Week 03 needed for the same structural reason:
# the resource being managed is the hierarchy itself.
resource "google_organization_iam_member" "apply_org_security_policy_admin" {
  org_id = var.org_id
  role   = "roles/compute.orgSecurityPolicyAdmin"
  member = google_service_account.apply.member
}

# The plan identity needs to READ every one of the above, or a refresh fails the
# way Week 01's did on resourcemanager.folders.get — a plan that cannot see a
# resource reports it as needing creation, which is how a plan proposes to
# rebuild something that already exists.
#
# roles/compute.viewer, not roles/viewer. The distinction is the one this file
# already argues at length: a compute-scoped read role reads compute, where a
# basic role reads every object in every bucket in the organization.
resource "google_folder_iam_member" "plan_compute_viewer" {
  for_each = toset([local.platform_folder, local.workloads_folder])

  folder = each.value
  role   = "roles/compute.viewer"
  member = google_service_account.plan.member
}

# Shared VPC host and attachment state is read at the organization, not at the
# folder, so the plan identity needs the org-level read counterpart to
# xpnAdmin. roles/compute.xpnAdmin has no read-only sibling that covers it;
# compute.networkViewer at the organization is the narrowest thing that does,
# and it confers reading network configuration only.
resource "google_organization_iam_member" "plan_network_viewer" {
  org_id = var.org_id
  role   = "roles/compute.networkViewer"
  member = google_service_account.plan.member
}

# ---------------------------------------------------------------------------
# Quota project consumers, added for Week 04
#
# A hierarchical firewall policy hangs off a folder and is owned by no project.
# The Compute API is client-based, so it attributes the call to the CALLER's
# quota project — and with none set it fails with
# "Error 404: The resource 'projects/null' was not found", which reads like a
# missing resource rather than a missing header.
#
# The fix is user_project_override plus billing_project on the provider, and the
# consequence is that every call then needs serviceusage.services.use on that
# quota project. Both identities need it: the plan identity refreshes the policy,
# the apply identity writes it.
#
# roles/serviceusage.serviceUsageConsumer is the narrowest role that carries it —
# permission to consume services and quota in one project, and nothing else. Not
# to be confused with serviceUsageAdmin, which tf-apply already holds at the
# organization and which ENABLES services; consuming and enabling are different
# verbs and this is deliberately the smaller one.
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "quota_consumer" {
  for_each = {
    plan  = google_service_account.plan.member
    apply = google_service_account.apply.member
  }

  project = "katta698-gcp-net-hub"
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = each.value
}

# Attaching a firewall policy to a folder is a DIFFERENT role from creating one,
# and the role names do not signal it. Measured 2026-09-12 by reading both role
# definitions after the association was refused:
#
#   roles/compute.orgSecurityPolicyAdmin    compute.firewallPolicies.create,
#                                           .update, .use  — and NOT
#                                           compute.organizations.setFirewallPolicy
#
#   roles/compute.orgSecurityResourceAdmin  compute.organizations.setFirewallPolicy,
#                                           compute.organizations.listAssociations
#
# So tf-apply could create the policy and could not attach it. That split is
# reasonable once stated — a policy attached to nothing is inert, so attachment
# is the act that actually changes behaviour — but nothing in the names says so,
# and the error names a permission without naming a role that grants it.
#
# Granted at the workloads folder rather than the organization: this identity
# should be able to attach policies to the branch that holds workloads, not to
# the organization root, where an association governs every project including
# the platform projects that run the lab itself.
resource "google_folder_iam_member" "apply_folder_security_resource_admin" {
  folder = local.workloads_folder
  role   = "roles/compute.orgSecurityResourceAdmin"
  member = google_service_account.apply.member
}

# ---------------------------------------------------------------------------
# Tag administration, added for Week 05
#
# Week 05 creates an organization-level tag key and its permitted values. Tags
# are IAM-controlled resources — that is the whole difference between a tag and
# a label, and the reason an organization policy can condition on one and not
# the other — so creating them needs a role tf-apply did not hold.
#
# Granted at the organization because a tag key defined at a folder is not
# visible above it, and this key is meant to be bindable anywhere in the
# hierarchy.
#
# Here rather than in Week 05 for the reason this file has argued twice before:
# an identity must not manage its own grants. Week 04 needed the same treatment
# for compute, and the pattern is now the norm rather than the exception — a new
# week that CI cannot yet perform is a signal to widen CI deliberately, in the
# human-run layer, not to quietly add a binding next to the resource that needs
# it.
# ---------------------------------------------------------------------------

resource "google_organization_iam_member" "apply_tag_admin" {
  org_id = var.org_id
  role   = "roles/resourcemanager.tagAdmin"
  member = google_service_account.apply.member
}

# tagAdmin creates tag keys and values. It does NOT bind them to anything —
# roles/resourcemanager.tagAdmin carries no tagValueBindings.create, and
# roles/resourcemanager.tagUser does. Confirmed 2026-09-19 by reading both role
# definitions after the binding was refused with a bare
# "Error 403: The caller does not have permission", which names neither the
# permission nor a role.
#
# The same split Week 04 hit with firewall policies: creating the thing and
# attaching the thing are separately authorised, and the role names do not say
# so. It is defensible — a tag value that is bound to nothing changes no
# behaviour, so binding is the act with consequences — but it is discovered
# rather than read.
resource "google_organization_iam_member" "apply_tag_user" {
  org_id = var.org_id
  role   = "roles/resourcemanager.tagUser"
  member = google_service_account.apply.member
}

# The read counterpart. A plan that cannot see the tag key reports it as needing
# creation, which is how a plan proposes to rebuild something that already
# exists.
resource "google_organization_iam_member" "plan_tag_viewer" {
  org_id = var.org_id
  role   = "roles/resourcemanager.tagViewer"
  member = google_service_account.plan.member
}

# Essential Contacts, added for Week 05.
#
# The factory sets an essential contact on every project it builds, because
# Google sends security bulletins, deprecation notices and suspension warnings
# to Essential Contacts and to nobody else — a project with none is one where
# the notice that something leaked goes to an address that does not exist.
#
# Creating a project does not confer the ability to administer its contacts.
# That surfaced as a bare "Error 403: The caller does not have permission" on
# the contact resource, after the project itself had been created successfully
# by the same identity moments earlier.
resource "google_organization_iam_member" "apply_essential_contacts" {
  org_id = var.org_id
  role   = "roles/essentialcontacts.admin"
  member = google_service_account.apply.member
}

resource "google_organization_iam_member" "plan_essential_contacts" {
  org_id = var.org_id
  role   = "roles/essentialcontacts.viewer"
  member = google_service_account.plan.member
}

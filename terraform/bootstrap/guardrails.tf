/*
 * Cost guardrails that REFUSE, not alert.
 *
 * The budget in main.tf says it plainly in its own comment: it is an alert,
 * not a cap. Google Cloud does not stop spending when a budget is exceeded.
 * Nothing in this lab refused an expensive resource until 2026-11-22; eleven
 * org policies were enforced and every one of them was about security.
 *
 * These live in bootstrap on purpose. A week folder's `terraform destroy`
 * removes what that week created - which is exactly how the Week 06 budget
 * disappeared - and a guardrail that a lab week can delete is not a guardrail.
 * Bootstrap is applied once and never torn down, and these are set at the
 * ORGANIZATION, so no folder or project beneath it can opt out: a project-level
 * policy cannot override an organization policy that is enforced without
 * allowing it.
 *
 * What these CANNOT do is covered in docs/COST-GUARDRAILS.md. The short
 * version: they cap unit price, not quantity, and nothing here stops a
 * thousand cheap things or one small thing left running for a month.
 */

locals {
  # Everything this lab has ever legitimately needed. Week 04 and Week 13 used
  # e2-micro; nothing has needed more. Widening this list is a deliberate commit
  # with a reason, which is the point of it being here rather than in a week.
  allowed_machine_types = ["e2-micro", "e2-small", "e2-medium", "f1-micro", "g1-small"]

  # The CEL sees the machine type as a URL ending in /machineTypes/<name>, so
  # anchor on the final segment rather than a substring: "contains('e2-micro')"
  # would also admit a future "e2-micro-metal" if Google ever shipped one.
  machine_type_condition = join(" || ", [
    for t in local.allowed_machine_types :
    "resource.machineType.endsWith('/${t}')"
  ])

  # Services with a high ENTRY price that no week on the 58-week roadmap uses.
  # Deliberately conservative: Spanner (Week 38), AlloyDB (37), Dataflow (40),
  # GKE (26-31), Apigee (45), Filestore and Managed Lustre (33) are all on the
  # roadmap and are NOT denied here, however expensive they are. Denying
  # something a future week needs would be a worse failure than not denying.
  denied_services = [
    "vmwareengine.googleapis.com",      # GCVE: minimum node commitment, thousands/month
    "baremetalsolution.googleapis.com", # Bare Metal Solution: monthly minimums
    "datafusion.googleapis.com",        # Data Fusion: priced per instance-hour, Basic ~$1.80/hr
    "composer.googleapis.com",          # Cloud Composer: an idle environment still bills
    "bigtable.googleapis.com",          # Bigtable: billed per node, no scale-to-zero
    "gkemulticloud.googleapis.com",     # Attached/multi-cloud clusters, per-cluster fee
  ]
}

# ---------------------------------------------------------------------------
# VM size
# ---------------------------------------------------------------------------

resource "google_org_policy_custom_constraint" "machine_types" {
  count = var.org_id == null ? 0 : 1

  name         = "custom.restrictMachineTypesToSmall"
  parent       = "organizations/${var.org_id}"
  display_name = "Only small machine types"
  description  = "A lab VM is an instrument, not a workload. Allowed: ${join(", ", local.allowed_machine_types)}."

  resource_types = ["compute.googleapis.com/Instance"]
  method_types   = ["CREATE", "UPDATE"]
  action_type    = "ALLOW"
  condition      = local.machine_type_condition
}

resource "google_org_policy_policy" "machine_types" {
  count = var.org_id == null ? 0 : 1

  name   = "organizations/${var.org_id}/policies/${google_org_policy_custom_constraint.machine_types[0].name}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# ---------------------------------------------------------------------------
# Database tier
# ---------------------------------------------------------------------------

resource "google_org_policy_custom_constraint" "sql_tiers" {
  count = var.org_id == null ? 0 : 1

  name         = "custom.restrictCloudSqlToSmallTiers"
  parent       = "organizations/${var.org_id}"
  display_name = "Only the smallest usable Cloud SQL tiers"
  description  = "Shared-core and 1-vCPU custom tiers only. Week 36 builds the Cloud SQL platform; it does not need a large instance to do it."

  resource_types = ["sqladmin.googleapis.com/Instance"]
  method_types   = ["CREATE", "UPDATE"]
  action_type    = "ALLOW"
  condition = join(" || ", [
    "resource.settings.tier.startsWith('db-f1-')",
    "resource.settings.tier.startsWith('db-g1-')",
    "resource.settings.tier == 'db-custom-1-3840'",
  ])
}

resource "google_org_policy_policy" "sql_tiers" {
  count = var.org_id == null ? 0 : 1

  name   = "organizations/${var.org_id}/policies/${google_org_policy_custom_constraint.sql_tiers[0].name}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# ---------------------------------------------------------------------------
# Services never used, whose entry price is high
#
# A DENY list rather than an allow list: an allow list would have to be edited
# before every new week, and the first time it blocked a legitimate week
# somebody would widen it in a hurry and leave it wide.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "denied_services" {
  count = var.org_id == null ? 0 : 1

  name   = "organizations/${var.org_id}/policies/gcp.restrictServiceUsage"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        denied_values = local.denied_services
      }
    }
  }
}

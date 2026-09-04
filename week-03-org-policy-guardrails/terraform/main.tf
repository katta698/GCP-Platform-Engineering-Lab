/*
 * Week 03 — Organization policy and guardrails.
 *
 * This organization did not start empty. Seven constraints were already
 * enforced before anyone in this lab wrote a line of policy, and reading them
 * back showed all seven carrying the same updateTime to within a fraction of a
 * second — one batch, applied by Google at organization creation, not a set that
 * accumulated. Week 02 was built on two of them.
 *
 * So the week is not "turn on some guardrails". It is: work out what the
 * platform already decided, add only what it did not, and prove the additions
 * are safe before they can deny anything.
 *
 * Three properties of the Organization Policy Service drive every choice below.
 *
 *   1. Policy inherits downward, and the CLOSEST policy wins. A policy written
 *      at a folder replaces the organization's for everything beneath it. It
 *      does not merge, and it does not have to be stricter.
 *
 *   2. Therefore a policy written at the organization on a constraint the
 *      baseline already set REPLACES that baseline spec. Hardening and loosening
 *      are the same API call with different contents. This is why nothing here
 *      touches a constraint that is already set — see the block at the foot.
 *
 *   3. A dry-run spec is evaluated on every request and logged when it WOULD
 *      have denied, while denying nothing. That is what makes it possible to
 *      find out what a constraint breaks before it breaks it.
 *
 * Every constraint here is written on the v2 resources. The v1
 * google_organization_policy resource cannot express a `.managed.` constraint at
 * all (hashicorp/terraform-provider-google#21401), so writing this week against
 * legacy constraint names would not be a stylistic choice — it would teach the
 * retiring API.
 */

# ---------------------------------------------------------------------------
# The API
#
# Organization policy is not stored in a project, so it is easy to assume no
# project needs anything enabled. Not so: the write goes through the caller's
# quota project, and that project must have orgpolicy.googleapis.com on.
#
# The plan gave no hint of this, and could not have. A plan only reads, and
# READING organization policy requires nothing enabled — the seven baseline
# constraints came back cleanly. The dependency appears at the first write and
# nowhere earlier, so "plan is clean" is not evidence the apply will work.
#
# Enabling an API in the same apply that uses it can still 403, because
# enablement takes a moment to propagate and depends_on does not wait for
# propagation, only for resource creation. If the first apply fails that way, run
# it again — that is the fix, not a bug to chase.
# ---------------------------------------------------------------------------

resource "google_project_service" "orgpolicy" {
  project = var.seed_project_id
  service = "orgpolicy.googleapis.com"

  disable_on_destroy = false
}

# Reading the dry-run violations is not an optional extra of this week, it is the
# step that decides whether a constraint may be enforced. A dry-run policy that
# nobody can read the output of is just a policy that does nothing.
#
# The API is enabled on the project that will be quoted as the quota project for
# the read, which is the seed project — same reasoning as orgpolicy above. The
# violations themselves are written at the organization, not here.
resource "google_project_service" "logging" {
  project = var.seed_project_id
  service = "logging.googleapis.com"

  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Where the exception goes
#
# Resolved by display name rather than carried as a folder ID in tfvars. See the
# reasoning on the variables. `folders list --organization` returns only direct
# children, so workloads/dev needs a second lookup rather than a filter.
# ---------------------------------------------------------------------------

data "google_folders" "root" {
  parent_id = "organizations/${var.org_id}"
}

locals {
  workloads_folder = one([
    for f in data.google_folders.root.folders : f.name
    if f.display_name == var.workloads_folder_name
  ])
}

data "google_folders" "workloads" {
  parent_id = local.workloads_folder
}

locals {
  dev_folder = one([
    for f in data.google_folders.workloads.folders : f.name
    if f.display_name == var.dev_folder_name
  ])
}

# ---------------------------------------------------------------------------
# The additions
#
# Three boolean managed constraints, chosen against what the read showed was
# absent rather than from a hardening checklist.
#
# It was four. iam.managed.disableServiceAccountApiKeyCreation was removed on
# 2026-09-03 after it turned out to be enforced already — not by the inherited
# baseline, but by a Google DEFAULT carried on the managed constraint itself,
# with parameters.allowedServices exempting the Gemini API.
#
# It was picked because it did not appear in `gcloud org-policies list`. That
# command shows only policies explicitly SET; a managed constraint can be fully
# enforced with no policy set on it, and the default shows up in neither `list`
# nor plain `describe`. Only `--effective` reveals it. The console had said so
# all along — 26 active organization policies against `list`'s 12.
#
# Adding a dry-run policy to an already-enforced constraint is not harmless
# either. It reports "dry-run" for something live, which is precisely the
# confusion this week is written to remove.
#
# The three that remain are boolean and take no parameters. That was originally a
# precaution — the reference documentation describes what the parameterised
# managed constraints do without publishing their parameter schemas, and a
# guessed schema is not a measurement. The precaution turned out to be
# unnecessary for the wrong reason: --effective PRINTS the schema, which is how
# allowedServices above became a known field rather than a guess.
#
# Each is keyed by its full constraint name so that var.enforce, the README and
# the resource address all say the same string.
#
# ---------------------------------------------------------------------------
# Why these are separate resources and not one for_each
#
# They were one for_each, over the map below. It is shorter, it reads better, and
# it does not work.
#
# The Organization Policy API serializes changes per parent. Terraform's default
# parallelism is 10, so it opened several SetPolicy calls against the same
# organization at once and the API rejected them with HTTP 409,
# reason CONCURRENT_POLICY_CHANGES, "Please retry the request". Partially, and
# differently each run: the first attempt landed two of the four then in flight
# before failing.
#
# The CLI answer to that is -parallelism=1. It is not available here:
#
#   Error: Custom parallelism values are currently not supported
#   HCP Terraform does not support setting a custom parallelism value at this time.
#
# That is the whole lesson, and it is a consequence of this being the first week
# to run remotely. On local execution the fix is a flag, which means the
# configuration can stay wrong and the operator remembers the workaround. On
# remote execution there is no flag to reach for, so the ordering has to be an
# edge in the dependency graph — a property of the code, which survives being run
# by someone who was not told.
#
# So: one chain, each policy depending on the one before it. The verbosity is the
# serialization; it is not incidental and should not be refactored away.
# ---------------------------------------------------------------------------

locals {
  boolean_constraints = {
    # Removes SSH key management from the instance and puts it behind IAM, so
    # access is granted and revoked centrally and every session is attributable
    # to a Google identity rather than to whoever holds a key.
    "compute.managed.requireOsLogin" = "Access to VMs goes through IAM, not through keys pasted into metadata."

    # Project-wide SSH keys apply to every instance in the project at once,
    # including instances created after the key was added. That is the opposite
    # of least privilege by default.
    "compute.managed.blockProjectSshKeys" = "A key added to a project must not silently grant access to VMs that do not exist yet."

    # The serial console bypasses the network path entirely: no firewall rule,
    # no VPC, no load balancer sees it. That is exactly why it is useful for
    # debugging a VM that will not boot, and exactly why it is a way in that the
    # network controls cannot see. Enforced everywhere, excepted at dev below.
    "compute.managed.disableSerialPortAccess" = "The serial console is a path in that no network control observes."
  }

  # Resolved once here so the four resources below and the enforcement_state
  # output cannot drift apart on how the switch is read.
  enforced = {
    for k, _ in local.boolean_constraints : k => lookup(var.enforce, k, false)
  }
}

# spec and dry_run_spec are mutually exclusive by construction below, and the
# switch is per-constraint. A policy carrying only a dry_run_spec is evaluated
# and logged but denies nothing, so a constraint sits in dry run until its own
# violations have been read, then graduates alone.
#
# The two dynamic blocks in each resource are inverses of one lookup. A single
# boolean for the whole set would flip four constraints on one commit and lose
# the ability to say which of them an audit log entry belonged to.

resource "google_org_policy_policy" "require_os_login" {
  name   = "organizations/${var.org_id}/policies/compute.managed.requireOsLogin"
  parent = "organizations/${var.org_id}"

  depends_on = [google_project_service.orgpolicy]

  dynamic "spec" {
    for_each = local.enforced["compute.managed.requireOsLogin"] ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = local.enforced["compute.managed.requireOsLogin"] ? [] : [1]
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }
}

resource "google_org_policy_policy" "block_project_ssh_keys" {
  name   = "organizations/${var.org_id}/policies/compute.managed.blockProjectSshKeys"
  parent = "organizations/${var.org_id}"

  # The chain. Not a real data dependency — this policy needs nothing the
  # previous one produces. It is an ordering edge, and the only way to express
  # "one at a time" when the runner will not accept -parallelism.
  depends_on = [google_org_policy_policy.require_os_login]

  dynamic "spec" {
    for_each = local.enforced["compute.managed.blockProjectSshKeys"] ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = local.enforced["compute.managed.blockProjectSshKeys"] ? [] : [1]
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }
}

resource "google_org_policy_policy" "disable_serial_port_access" {
  name   = "organizations/${var.org_id}/policies/compute.managed.disableSerialPortAccess"
  parent = "organizations/${var.org_id}"

  depends_on = [google_org_policy_policy.block_project_ssh_keys]

  dynamic "spec" {
    for_each = local.enforced["compute.managed.disableSerialPortAccess"] ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = local.enforced["compute.managed.disableSerialPortAccess"] ? [] : [1]
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }
}


# The two policies created before the concurrency failure were addressed by map
# key. Renaming them to serialize the chain is a pure address change — the
# policies in Google Cloud are untouched — so `moved` carries the state across
# rather than destroying and recreating live organization policy.
#
# The other two blocks name addresses that were never created. A `moved` block
# whose source is absent from state is a no-op, so all four are listed and the
# set stays readable as one unit.
moved {
  from = google_org_policy_policy.org["compute.managed.requireOsLogin"]
  to   = google_org_policy_policy.require_os_login
}

moved {
  from = google_org_policy_policy.org["compute.managed.blockProjectSshKeys"]
  to   = google_org_policy_policy.block_project_ssh_keys
}

moved {
  from = google_org_policy_policy.org["compute.managed.disableSerialPortAccess"]
  to   = google_org_policy_policy.disable_serial_port_access
}

# ---------------------------------------------------------------------------
# The exception, and why it is written down rather than granted quietly
#
# Serial console access is refused across the organization. In workloads/dev it
# is allowed, because the thing the constraint defends against and the thing dev
# needs are the same thing: a way to see a machine that is too broken to reach
# over the network.
#
# The alternative to writing this is worse. Without a stated exception, the first
# engineer with an unbootable dev VM either waits, or asks for the organization
# policy to be turned off — and it gets turned off at the organization, for
# everything, because that is where it was set. An exception at the narrowest
# node is what keeps the enforcement at every other node credible.
#
# enforce = "FALSE" at the folder, not a reset. A reset would return dev to
# whatever it inherits, which is enforcement; the override has to be explicit.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "dev_serial_port_exception" {
  name   = "${local.dev_folder}/policies/compute.managed.disableSerialPortAccess"
  parent = local.dev_folder

  spec {
    rules {
      enforce = "FALSE"
    }
  }

  # Only meaningful once the organization-level policy it excepts is enforced.
  # While that one is in dry run this resource is a no-op against a no-op, which
  # is harmless and is why it is not gated behind the same switch.
  depends_on = [google_org_policy_policy.disable_serial_port_access]
}

# ---------------------------------------------------------------------------
# One custom constraint
#
# Predefined constraints cover what Google anticipated. A custom constraint is
# how an organization's own rule becomes something the platform enforces rather
# than something a reviewer has to notice.
#
# The rule chosen is this lab's own: every resource carries week, env and
# managed-by labels. That has been written in the repository's contributing
# instructions since Week 01, which means it has been enforced by nothing.
# A label convention that lives only in a document is a convention that is
# already half broken and nobody has looked.
#
# Buckets rather than VMs as the target, for a reason worth stating: this lab
# runs no compute, so a constraint on instances could not be tested without
# spending money to violate it. Bucket creation is free, so the denial is
# demonstrable, which matters more than the resource type being interesting.
#
# action_type ALLOW means the request proceeds only when the condition is true.
# ---------------------------------------------------------------------------

resource "google_org_policy_custom_constraint" "bucket_labels" {
  name   = "custom.requireTerraformLabelsOnBuckets"
  parent = "organizations/${var.org_id}"

  display_name = "Require week, env and managed-by labels on buckets"
  description  = "Storage buckets must carry the three labels this lab requires of every resource. managed-by must be terraform, so a bucket created by hand in the console is refused."

  # Also chained. A custom constraint is a different API resource from a policy,
  # but it is written against the same parent, and the 409 is raised per parent.
  depends_on = [google_org_policy_policy.disable_serial_port_access]

  action_type    = "ALLOW"
  method_types   = ["CREATE", "UPDATE"]
  resource_types = ["storage.googleapis.com/Bucket"]

  # UPDATE is included alongside CREATE on purpose. Without it the labels can be
  # stripped the moment after the bucket exists, and the constraint would only
  # ever have been a formality at creation time.
  condition = join(" && ", [
    "has(resource.labels)",
    "'week' in resource.labels",
    "'env' in resource.labels",
    "'managed-by' in resource.labels",
    "resource.labels['managed-by'] == 'terraform'",
  ])
}

# A custom constraint that is defined but not referenced by a policy enforces
# nothing at all — defining it only makes the name available to be set. That
# separation is easy to miss, because the definition alone looks complete in the
# console.
resource "google_org_policy_policy" "bucket_labels" {
  name   = "organizations/${var.org_id}/policies/${google_org_policy_custom_constraint.bucket_labels.name}"
  parent = "organizations/${var.org_id}"

  dynamic "spec" {
    for_each = lookup(var.enforce, "custom.requireTerraformLabelsOnBuckets", false) ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = lookup(var.enforce, "custom.requireTerraformLabelsOnBuckets", false) ? [] : [1]
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# What is deliberately NOT here: the seven constraints already set
#
# The obvious move on reading the baseline is to bring those seven into Terraform
# so the whole policy surface is in code. It is the wrong move, and the reason is
# property 2 at the top of this file.
#
# Writing them here does not "adopt" them. It issues SetPolicy at the
# organization with whatever this file says, replacing the inherited spec. Two of
# them carry parameters read out of the live organization — an allowed contact
# domain, and a customer ID on iam.allowedPolicyMemberDomains — and those values
# are account identifiers that must not be committed. So codifying them means
# either hardcoding identifiers into a public repository, or plumbing them
# through tfvars to reproduce a spec Google already applies correctly.
#
# The failure mode is quiet. A transcription slip in a parameter does not error;
# it applies, and the organization is left less protected than it was, with a
# Terraform state file asserting that everything is managed. The baseline is
# already enforced, by an owner that is not this configuration. Leave it there,
# and let this week's own additions be the thing this state is responsible for.
#
# The baseline is also visibly mid-migration, which is worth knowing before
# trusting any generalisation about constraint naming: it sets
# iam.managed.disableServiceAccountKeyCreation on the managed generation, and
# iam.disableServiceAccountKeyUpload on the legacy one — even though
# iam.managed.disableServiceAccountKeyUpload exists and is available on this
# organization. Google's own default set does not use one generation throughout.
# ---------------------------------------------------------------------------

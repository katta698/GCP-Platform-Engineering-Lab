terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-04"
    }
  }
}

# Runs as tf-apply through workload identity federation, same as Week 03. What
# changed is what tf-apply is allowed to do: Week 02 was amended to grant it
# compute.networkAdmin on the platform and workloads folders,
# compute.instanceAdmin.v1 on workloads, and compute.xpnAdmin plus
# compute.orgSecurityPolicyAdmin at the organization.
#
# Those grants are deliberately NOT in this configuration. An identity must not
# manage its own grants — see the block in week-02-keyless-ci/terraform/main.tf.
# user_project_override and billing_project are not decoration. A hierarchical
# firewall policy hangs off a FOLDER, so it is owned by no project — and the
# Compute API is client-based, meaning it bills and quotas against the caller's
# project rather than the resource's. With no quota project to attribute the call
# to, the API returns:
#
#   Error 404: The resource 'projects/null' was not found
#
# which reads like a missing project rather than a missing header. The bootstrap
# hit the identical thing on the Budgets API in August; the lesson is recorded in
# SESSION_CONTEXT and was still not obvious from the error text here.
#
# The provider does not send X-Goog-User-Project unless user_project_override is
# true, so setting billing_project alone is not enough.
provider "google" {
  project = var.host_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.host_project_id
}

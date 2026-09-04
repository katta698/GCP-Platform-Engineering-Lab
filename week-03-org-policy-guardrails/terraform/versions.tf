terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # One workspace, no -dev / -prod suffix. Organization policy is set once, at the
  # organization, and inherits downward; the environment distinction this week
  # makes is a folder-level exception written from here, not a second deployment.
  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-03"
    }
  }
}

# The first week with no hand-run apply. Credentials arrive from the workload
# identity pool Week 02 built: HCP mints an OIDC token per run, Google's STS
# exchanges it, and tf-apply — which already holds roles/orgpolicy.policyAdmin at
# the organization — does the writing. Nothing here supplies a credential,
# because there is no credential to supply.
provider "google" {
  project = var.seed_project_id
  region  = var.region
}

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
      name = "gcp-week-11"
    }
  }
}

# Nothing exotic here. Privileged Access Manager is a normal resource-oriented
# API: the entitlement hangs off the folder it grants access on, so the call is
# attributed to that resource and no quota-project override is needed. Week 10
# needed user_project_override because Cloud Identity bills the CALLER and a
# group belongs to no project; this week has neither problem.
provider "google" {
  project = var.seed_project_id
  region  = var.region
}

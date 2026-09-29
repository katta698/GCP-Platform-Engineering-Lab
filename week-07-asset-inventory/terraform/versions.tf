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
      name = "gcp-week-07"
    }
  }
}

# Cloud Asset Inventory is a client-based API: every call is billed and
# attributed to the caller's quota project, not to the organization being
# inventoried. Without an explicit quota project the failure is a 403 telling
# you to set one you believe you have already set. Same reasoning as Weeks 04
# through 06.
provider "google" {
  project = var.seed_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.seed_project_id
}

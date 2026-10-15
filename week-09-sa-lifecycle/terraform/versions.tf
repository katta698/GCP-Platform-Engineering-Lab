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
      name = "gcp-week-09"
    }
  }
}

# The IAM API is client-based, same as every week since 04:
# calls are attributed to the caller's quota project, not to the organization
# being inventoried.
provider "google" {
  project = var.seed_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.seed_project_id
}

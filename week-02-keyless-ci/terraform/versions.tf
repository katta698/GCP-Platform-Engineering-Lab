terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # One workspace, no -dev / -prod suffix. The federation trust is org-wide:
  # there is exactly one pool and one provider, and the environments are
  # distinguished inside the token's claims rather than by deploying this twice.
  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-02"
    }
  }
}

# The last apply in this lab that runs from a human's credentials. Everything
# after this week authenticates through the pool created below.
provider "google" {
  project = var.seed_project_id
  region  = var.region
}

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # No -dev / -prod suffix on this workspace. The hierarchy is org-wide: there is
  # exactly one set of folders, and dev and prod are objects *inside* it rather
  # than separate deployments of it. Week 20 onwards, where a week really does
  # deploy twice, uses gcp-week-NN-dev and gcp-week-NN-prod.
  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-01"
    }
  }
}

provider "google" {
  region = var.region
}

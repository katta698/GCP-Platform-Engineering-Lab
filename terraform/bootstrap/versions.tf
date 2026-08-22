terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # State lives in HCP Terraform, same as the AWS lab, under the
  # "GCP Platform Lab" project. Migrated from the GCS backend 2026-08-21.
  #
  # Execution is local for now: remote runs need GCP credentials in HCP, which
  # is Workload Identity Federation and is set up in Week 05. Until then the
  # runs happen on the workstation against ADC and only state is remote.
  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-bootstrap"
    }
  }
}

# No `project` here on purpose. This configuration creates the project it works
# in, so a provider-level project reference would be unresolvable on the first
# plan. Every resource below sets `project` explicitly instead.
provider "google" {
  region = var.region
}

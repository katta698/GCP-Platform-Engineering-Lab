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
      name = "gcp-week-10"
    }
  }
}

# Cloud Identity is a client-based API: it bills the CALLER's project rather
# than the resource being addressed, and the resource here - a group - does not
# belong to a project at all. Without user_project_override the provider never
# sends X-Goog-User-Project and the call is attributed to gcloud's own shared
# client project, which returns SERVICE_DISABLED naming a project number nobody
# recognises.
#
# Measured on the CLI first, 2026-10-23: `gcloud identity groups search` fails
# with PERMISSION_DENIED / SERVICE_DISABLED (consumer: a Google-owned project)
# even with the ADC quota project set, and succeeds with an explicit
# --billing-project. These two lines are the Terraform spelling of that flag.
provider "google" {
  project = var.seed_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.seed_project_id
}

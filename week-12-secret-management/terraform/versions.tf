terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    # google-beta is here for exactly one resource:
    # google_project_service_identity. Creating a secret with a
    # customer-managed key requires the Secret Manager service agent to already
    # exist, because the agent - not the caller - performs every encrypt and
    # decrypt. That agent is created on demand and there is no GA Terraform
    # resource that creates one. The alternative is a hand-run
    # `gcloud beta services identity create`, which would make the config
    # un-appliable from a clean slate.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    # Generates the secret's initial value, so no credential - not even a
    # throwaway one - is ever written into a file in a public repository.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Zips the rotator source for Cloud Functions. Only used in stage 2.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-12"
    }
  }
}

# No user_project_override this week. Cloud KMS, Secret Manager and Pub/Sub are
# all resource-oriented: every call is attributed to the project the key, secret
# or topic lives in. Week 06 (Budgets) and Week 10 (Cloud Identity) needed the
# override because those APIs bill the CALLER; nothing here does.
provider "google" {
  project = var.security_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.security_project_id
  region  = var.region
}

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

# user_project_override IS required here, and an earlier version of this file
# confidently said it was not. The comment claimed Cloud KMS, Secret Manager and
# Pub/Sub are "resource-oriented, so every call is attributed to the project the
# key lives in". The deployment disagreed:
#
#   Cloud Key Management Service (KMS) API has not been used in project
#   <SEED-PROJECT-NUMBER> before or it is disabled
#
# The number Google named is the SEED project - where the pipeline's identity
# lives, not where the key goes. (Redacted: a project number is an account
# identifier, and this repository is public.) Without an explicit quota project the provider sends no
# X-Goog-User-Project header, so Google attributes the call to the project
# owning the CREDENTIALS. `cloudkms` is enabled on the security project and was
# never going to help, because the security project was not the project being
# asked.
#
# Setting billing_project to the security project puts the attribution back
# where the resources are, rather than enabling crypto APIs on the seed project
# - which would quietly make the seed project a place keys could live, undoing
# the separation the security project exists to provide.
#
# Same shape as Week 06 (Budgets) and Week 10 (Cloud Identity). The lesson
# generalises further than either of those weeks recorded: it is not that some
# APIs "bill the caller", it is that EVERY API bills the caller unless told
# otherwise.
provider "google" {
  project               = var.security_project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.security_project_id
}

provider "google-beta" {
  project               = var.security_project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.security_project_id
}

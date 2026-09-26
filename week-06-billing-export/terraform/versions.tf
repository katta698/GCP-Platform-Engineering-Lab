terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Solely for the propagation wait between relaxing an organization policy
    # and depending on that relaxation. See the budget in main.tf.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "gcp-week-06"
    }
  }
}

# user_project_override and billing_project again, for the reason Week 04
# established and Week 05 repeated. A budget hangs off a BILLING ACCOUNT, which
# sits outside the resource hierarchy entirely and is owned by no project — and
# the Budgets API is client-based, so it attributes the call to the caller's
# quota project. With none set the failure is a 403 telling you to set a quota
# project you believe you have already set.
#
# The seed project is the quota project rather than the data project: the
# billing API calls are control-plane work, and that is where this lab accounts
# control-plane work.
provider "google" {
  project = var.seed_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.seed_project_id
}

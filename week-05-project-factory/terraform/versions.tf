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
      name = "gcp-week-05"
    }
  }
}

# user_project_override and billing_project, for the reason Week 04 established
# the hard way. Tag keys, tag values and custom constraints all hang off the
# ORGANIZATION, so they are owned by no project — and these are client-based
# APIs, which attribute a call to the caller's quota project rather than the
# resource's. With none set, the failure is:
#
#   Error 404: The resource 'projects/null' was not found
#
# which points at a missing resource rather than a missing X-Goog-User-Project
# header. The provider does not send that header unless user_project_override is
# true, so billing_project alone is not enough.
#
# The seed project is the quota project rather than the network hub Week 04
# used: this week creates no network, and the seed project is where this lab's
# control-plane work is already accounted.
provider "google" {
  project = var.seed_project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.seed_project_id
}

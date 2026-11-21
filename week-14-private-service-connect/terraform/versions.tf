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
      name = "gcp-week-14"
    }
  }
}

provider "google" {
  project = var.net_hub_project_id
  region  = var.region
}

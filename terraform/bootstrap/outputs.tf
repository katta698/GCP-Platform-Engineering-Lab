output "seed_project_id" {
  description = "Project ID of the seed project."
  value       = google_project.seed.project_id
}

output "cloud_block" {
  description = "Ready-to-paste HCP Terraform configuration for a week's versions.tf."
  value       = <<-EOT
    cloud {
      organization = "Katta"

      workspaces {
        name = "gcp-week-NN-dev"
      }
    }
  EOT
}

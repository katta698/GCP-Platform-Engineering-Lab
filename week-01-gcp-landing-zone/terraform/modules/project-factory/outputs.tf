output "project_id" {
  description = "The created project's ID."
  value       = google_project.this.project_id
}

output "project_number" {
  description = <<-EOT
    The project's numeric ID. Needed for IAM member strings of the form
    serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com and for
    Workload Identity Federation principals.
  EOT
  value       = google_project.this.number
}

output "enabled_apis" {
  description = "APIs enabled on this project by the module."
  value       = [for s in google_project_service.this : s.service]
}

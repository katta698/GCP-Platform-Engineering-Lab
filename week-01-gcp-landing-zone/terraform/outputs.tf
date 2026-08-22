output "folder_platform" {
  description = "Resource name of the platform folder, as folders/NNNN."
  value       = google_folder.platform.name
}

output "folder_workloads" {
  description = "Resource name of the workloads folder."
  value       = google_folder.workloads.name
}

output "folder_dev" {
  description = "Resource name of the dev folder. Later weeks create their dev projects here."
  value       = google_folder.dev.name
}

output "folder_prod" {
  description = "Resource name of the prod folder."
  value       = google_folder.prod.name
}

output "platform_projects" {
  description = "Platform project IDs and numbers."
  value = {
    network_hub = { id = module.network_hub.project_id, number = module.network_hub.project_number }
    logging     = { id = module.logging.project_id, number = module.logging.project_number }
    security    = { id = module.security.project_id, number = module.security.project_number }
  }
}

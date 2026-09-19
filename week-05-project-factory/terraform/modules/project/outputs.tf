output "project_id" {
  description = "The project ID. Permanent, globally unique, and never released for reuse even after deletion."
  value       = google_project.this.project_id
}

output "number" {
  description = "The project number. Sensitive: it appears in service agent identities and in resource names that get screenshotted."
  value       = google_project.this.number
  sensitive   = true
}

output "name" {
  description = "Display name. Unlike the ID, this can be changed later."
  value       = google_project.this.name
}

output "enabled_apis" {
  description = "APIs this module enabled, so a caller can assert on the set rather than trusting the input was honoured."
  value       = sort([for s in google_project_service.this : s.service])
}

output "compliance" {
  description = <<-EOT
    The controls this module applied, as facts rather than inputs. A factory is
    only worth having if you can show what it enforced — and the useful question
    is not "what did the caller ask for" but "what does this project actually
    carry". Read back in validate.sh against the live project.
  EOT
  value = {
    labels_set         = keys(google_project.this.labels)
    environment_tag    = var.environment_tag_value_id
    default_network    = "not created"
    deletion_policy    = google_project.this.deletion_policy
    essential_contact  = "set"
    contact_categories = var.essential_contact_categories
    deletion_lien      = var.deletion_lien
  }
}

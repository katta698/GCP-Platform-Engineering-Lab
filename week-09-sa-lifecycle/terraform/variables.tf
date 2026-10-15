variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "seed_project_id" {
  description = "Quota project for the client-based IAM and Policy Intelligence APIs. See the note in versions.tf."
  type        = string
}

variable "logging_project_id" {
  description = "Project whose default Compute Engine service account has never authenticated."
  type        = string
  default     = "katta698-gcp-logging"
}

variable "security_project_id" {
  description = "Second project with an unused default Compute Engine service account."
  type        = string
  default     = "katta698-gcp-security"
}

variable "region" {
  description = "Default region. This week creates nothing regional; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

variable "project_id" {
  description = "Globally unique project ID. Lowercase letters, digits, hyphens; 6-30 chars."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "display_name" {
  description = "Human-readable project name shown in the console."
  type        = string
}

variable "folder_id" {
  description = "Folder to create the project in, as folders/NNNN."
  type        = string
}

variable "billing_account" {
  description = "Billing account to attach. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "activate_apis" {
  description = <<-EOT
    APIs to enable on the project. Deliberately empty by default — a project
    that enables nothing has the smallest possible surface, and each week adds
    only what it actually uses.
  EOT
  type        = list(string)
  default     = []
}

variable "week" {
  description = "Lab week that owns this project, for the `week` label."
  type        = string
}

variable "env" {
  description = "Environment for the `env` label: dev, prod, or shared."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "shared"], var.env)
    error_message = "env must be one of: dev, prod, shared."
  }
}

variable "labels" {
  description = "Extra labels merged over the defaults."
  type        = map(string)
  default     = {}
}

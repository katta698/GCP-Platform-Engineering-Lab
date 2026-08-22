variable "org_id" {
  description = "Numeric organization ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "billing_account" {
  description = "Billing account ID. Sensitive: never commit the value."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "network_hub_project_id" {
  description = "Project ID for the Shared VPC host project."
  type        = string
}

variable "logging_project_id" {
  description = "Project ID for the centralised logging project."
  type        = string
}

variable "security_project_id" {
  description = "Project ID for the security and key management project."
  type        = string
}

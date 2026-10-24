variable "seed_project_id" {
  description = "Seed project. Quota project for the Cloud Identity API and home of the demo service account."
  type        = string
}

variable "customer_id" {
  description = <<-EOT
    Cloud Identity directory customer ID, in the form C0123abcd.

    This is the parent of every group - groups hang off the CUSTOMER, not off
    the organization, the way every other resource in this lab does. It is an
    account identifier, so it lives in terraform.tfvars and never in git. Read
    it back with:

      gcloud organizations describe <ORG_ID> \
        --format="value(owner.directoryCustomerId)"
  EOT
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Cloud Identity primary domain. Group addresses are formed from it."
  type        = string
}

variable "platform_folder_id" {
  description = <<-EOT
    Folder the group's role is granted on, as folders/NNNN.

    FOLDER, not organization, and that is a consequence of Week 02 rather than a
    preference. `tf-apply` deliberately does not hold
    roles/resourcemanager.organizationAdmin - an identity must not be able to
    grant itself anything - and organization-level setIamPolicy lives only in
    that role. It does hold roles/resourcemanager.folderAdmin, which carries
    folders.setIamPolicy.

    So the pipeline cannot bind a principal at the organization and can bind one
    at a folder. Narrower is the correct answer anyway; here it is also the only
    answer the pipeline can execute.
  EOT
  type        = string
}

variable "operator_principal" {
  description = <<-EOT
    The human who runs the revocation test, as a bare email address.

    Needed because the test subject is a service account that holds nothing
    directly, and somebody has to be able to mint a token as it. Granted
    roles/iam.serviceAccountTokenCreator on that one account and nothing else.

    A personal identifier, so it stays in terraform.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Default region. This week creates nothing regional; it is here so the provider block matches every other week."
  type        = string
  default     = "us-central1"
}

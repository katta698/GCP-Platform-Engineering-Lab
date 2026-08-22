locals {
  labels = merge(
    {
      managed-by = "terraform"
      week       = var.week
      env        = var.env
    },
    var.labels,
  )
}

resource "google_project" "this" {
  name       = var.display_name
  project_id = var.project_id
  folder_id  = var.folder_id

  billing_account = var.billing_account

  # Without this, deleting the project leaves the default network behind and
  # the first firewall rule you write inherits rules you never chose. Every
  # network in this lab is created explicitly.
  auto_create_network = false

  labels = local.labels
}

resource "google_project_service" "this" {
  for_each = toset(var.activate_apis)

  project = google_project.this.project_id
  service = each.value

  # An API can be a dependency of something outside this module's view, so
  # turning it off during a destroy can break unrelated resources.
  disable_on_destroy = false
}

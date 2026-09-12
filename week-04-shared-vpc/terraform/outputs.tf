# Project numbers and folder IDs embed the hierarchy's numbering and are read on
# screen and screenshotted for the write-up. Marked sensitive to keep them out of
# the run log; `terraform output -raw` still prints one when it is needed.

output "network" {
  description = "The Shared VPC hub network."
  value       = google_compute_network.hub.name
}

output "subnets" {
  description = "Subnet name to range. The whole address plan, in one place — which is the argument for custom mode over auto mode."
  value = {
    (google_compute_subnetwork.dev.name)  = google_compute_subnetwork.dev.ip_cidr_range
    (google_compute_subnetwork.prod.name) = google_compute_subnetwork.prod.ip_cidr_range
  }
}

output "service_project" {
  description = "Service project attached to the host. Owns the workload, owns no network."
  value       = google_project.service.project_id
}

output "instance_internal_ip" {
  description = "The instance's address, from the dev subnet in the HOST project. That a service project's VM draws its address from another project's subnet is the whole of Shared VPC in one value."
  value       = google_compute_instance.dev_app.network_interface[0].network_ip
}

output "instance_has_external_ip" {
  description = "Must be false. An external IPv4 address bills per hour whether traffic flows or not, and is not in the free tier — so this output is a cost assertion, not a fact about connectivity."
  value       = length(google_compute_instance.dev_app.network_interface[0].access_config) > 0
}

output "free_tier_shape" {
  description = "The four choices that keep this week inside Always Free. Any one of them changed silently turns a free week into a billed one."
  value = {
    machine_type = google_compute_instance.dev_app.machine_type
    zone         = google_compute_instance.dev_app.zone
    disk_type    = google_compute_instance.dev_app.boot_disk[0].initialize_params[0].type
    disk_gb      = google_compute_instance.dev_app.boot_disk[0].initialize_params[0].size
  }
}

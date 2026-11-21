output "endpoint_ip" {
  description = "The PSC endpoint address. Calls to Google APIs go here instead of to a Google VIP."
  value       = google_compute_global_address.psc.address
}

output "subnet_cidr" {
  description = "The probe VM's subnet. The endpoint address is deliberately outside it."
  value       = google_compute_subnetwork.psc.ip_cidr_range
}

output "network" {
  description = "The VPC whose default internet-gateway route the PGA test deletes."
  value       = google_compute_network.psc.name
}

output "probe" {
  description = "The VM with no external IP that both halves of the test run from."
  value       = google_compute_instance.probe.name
}

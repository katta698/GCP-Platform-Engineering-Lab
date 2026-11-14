output "hub_router" {
  description = "Cloud Router on the hub side. validate.sh reads its BGP session states and learned routes from here."
  value       = google_compute_router.hub.name
}

output "branch_router" {
  description = "Cloud Router on the branch side."
  value       = google_compute_router.branch.name
}

output "tunnels" {
  description = "All four tunnel resources, which is what actually bills."
  value       = concat([for t in google_compute_vpn_tunnel.hub : t.name], [for t in google_compute_vpn_tunnel.branch : t.name])
}

output "branch_cidr" {
  description = "The range the branch advertises over BGP. Nothing static routes to it."
  value       = var.branch_cidr
}

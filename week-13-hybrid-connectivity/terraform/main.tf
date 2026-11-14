# Week 13 - HA VPN between two VPCs, with BGP doing the routing.
#
# The hub VPC is Week 04's. The branch VPC stands in for a remote site: the
# protocols are identical whether the peer is another VPC, on-premises
# hardware, or another cloud.

locals {
  labels = {
    week       = "13"
    env        = "platform"
    managed-by = "terraform"
  }

  # Week 03's constraints are enforced org-wide, so a VM that omits these
  # cannot be created at all: Error 412 on requireOsLogin and
  # blockProjectSshKeys. Week 04's VM predates enforcement and carries neither.
  os_policy_metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  # Link-local /30s for the BGP sessions. These are the router-to-router
  # addresses, not anything a workload uses.
  bgp = {
    t0 = { hub = "169.254.0.1", branch = "169.254.0.2" }
    t1 = { hub = "169.254.1.1", branch = "169.254.1.2" }
  }
}

data "google_compute_network" "hub" {
  name    = "hub"
  project = var.net_hub_project_id
}

# ---------------------------------------------------------------------------
# The branch side
# ---------------------------------------------------------------------------

resource "google_compute_network" "branch" {
  name                    = "branch"
  project                 = var.net_hub_project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "branch" {
  name          = "branch-${var.region}"
  project       = var.net_hub_project_id
  network       = google_compute_network.branch.id
  region        = var.region
  ip_cidr_range = var.branch_cidr
}

# ---------------------------------------------------------------------------
# Gateways
#
# Each HA VPN gateway gets two interfaces with their own public IPs. Using only
# one carries NO availability SLA - not a reduced one.
# ---------------------------------------------------------------------------

resource "google_compute_ha_vpn_gateway" "hub" {
  name    = "hub-gw"
  project = var.net_hub_project_id
  network = data.google_compute_network.hub.id
  region  = var.region
}

resource "google_compute_ha_vpn_gateway" "branch" {
  name    = "branch-gw"
  project = var.net_hub_project_id
  network = google_compute_network.branch.id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Cloud Routers
#
# These run BGP and program the learned routes into each VPC. They are control
# plane only - traffic does not flow through them.
# ---------------------------------------------------------------------------

resource "google_compute_router" "hub" {
  name    = "hub-router"
  project = var.net_hub_project_id
  network = data.google_compute_network.hub.id
  region  = var.region

  bgp {
    asn = var.hub_asn
  }
}

resource "google_compute_router" "branch" {
  name    = "branch-router"
  project = var.net_hub_project_id
  network = google_compute_network.branch.id
  region  = var.region

  bgp {
    asn = var.branch_asn
  }
}

# ---------------------------------------------------------------------------
# Tunnels - two per side, interface 0 to interface 0 and 1 to 1.
#
# Four tunnel RESOURCES for two logical tunnels, and each one bills separately
# at $0.05/hour.
# ---------------------------------------------------------------------------

resource "google_compute_vpn_tunnel" "hub" {
  for_each = { t0 = 0, t1 = 1 }

  name                  = "hub-to-branch-${each.key}"
  project               = var.net_hub_project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.hub.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.branch.id
  vpn_gateway_interface = each.value
  shared_secret         = var.shared_secret
  router                = google_compute_router.hub.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "branch" {
  for_each = { t0 = 0, t1 = 1 }

  name                  = "branch-to-hub-${each.key}"
  project               = var.net_hub_project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.branch.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub.id
  vpn_gateway_interface = each.value
  shared_secret         = var.shared_secret
  router                = google_compute_router.branch.id
  ike_version           = 2
}

# ---------------------------------------------------------------------------
# BGP: one router interface and one peer per tunnel, per side.
# ---------------------------------------------------------------------------

resource "google_compute_router_interface" "hub" {
  for_each = local.bgp

  name       = "hub-if-${each.key}"
  project    = var.net_hub_project_id
  region     = var.region
  router     = google_compute_router.hub.name
  ip_range   = "${each.value.hub}/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub[each.key].name
}

resource "google_compute_router_peer" "hub" {
  for_each = local.bgp

  name            = "hub-peer-${each.key}"
  project         = var.net_hub_project_id
  region          = var.region
  router          = google_compute_router.hub.name
  interface       = google_compute_router_interface.hub[each.key].name
  peer_ip_address = each.value.branch
  peer_asn        = var.branch_asn
}

resource "google_compute_router_interface" "branch" {
  for_each = local.bgp

  name       = "branch-if-${each.key}"
  project    = var.net_hub_project_id
  region     = var.region
  router     = google_compute_router.branch.name
  ip_range   = "${each.value.branch}/30"
  vpn_tunnel = google_compute_vpn_tunnel.branch[each.key].name
}

resource "google_compute_router_peer" "branch" {
  for_each = local.bgp

  name            = "branch-peer-${each.key}"
  project         = var.net_hub_project_id
  region          = var.region
  router          = google_compute_router.branch.name
  interface       = google_compute_router_interface.branch[each.key].name
  peer_ip_address = each.value.hub
  peer_asn        = var.hub_asn
}

# ---------------------------------------------------------------------------
# Test VMs and the firewall rules that let them reach each other.
# e2-micro in us-central1 with no external IP is free tier.
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "branch_allow_hub" {
  name    = "branch-allow-hub-icmp-ssh"
  project = var.net_hub_project_id
  network = google_compute_network.branch.name

  source_ranges = ["10.20.0.0/24", "10.20.1.0/24", "35.235.240.0/20"]

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "hub_allow_branch" {
  name    = "hub-allow-branch-icmp"
  project = var.net_hub_project_id
  network = data.google_compute_network.hub.name

  source_ranges = [var.branch_cidr]

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_instance" "hub_probe" {
  name         = "hub-probe"
  project      = var.net_hub_project_id
  zone         = "${var.region}-a"
  machine_type = "e2-micro"
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = "dev-${var.region}"
  }

  metadata = local.os_policy_metadata
}

resource "google_compute_instance" "branch_probe" {
  name         = "branch-probe"
  project      = var.net_hub_project_id
  zone         = "${var.region}-a"
  machine_type = "e2-micro"
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.branch.id
  }

  metadata = local.os_policy_metadata
}

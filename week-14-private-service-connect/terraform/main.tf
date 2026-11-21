/*
 * Week 14 - Private Service Connect for Google APIs, against Private Google
 * Access, in one VPC so the difference can be broken and restored.
 *
 * Its own VPC rather than Week 04's hub, for two reasons. The hub's subnets
 * already have private_ip_google_access enabled, so reusing them would mean
 * the week demonstrates something it did not build. And the test deletes the
 * default route to the internet gateway, which would degrade every other
 * workload on a shared network.
 *
 * The route this test deletes is NOT declared here. Google creates
 * default-route-<hash> when the network is created; Terraform never owns it,
 * so it cannot be removed by changing a variable. scripts/break-pga.sh deletes
 * it and puts it back.
 */

locals {
  labels = {
    week       = "14"
    env        = "platform"
    managed-by = "terraform"
  }

  # Week 03's constraints are enforced org-wide: a VM without these cannot be
  # created at all (Error 412 on requireOsLogin and blockProjectSshKeys).
  os_policy_metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }
}

# ---------------------------------------------------------------------------
# A network of its own, so deleting its default route harms nothing else.
# ---------------------------------------------------------------------------

resource "google_compute_network" "psc" {
  name                    = "psc-lab"
  project                 = var.net_hub_project_id
  auto_create_subnetworks = false
}

# private_ip_google_access is the whole of Private Google Access: a per-subnet
# boolean. It is one half of what this week compares.
resource "google_compute_subnetwork" "psc" {
  name                     = "psc-lab-${var.region}"
  project                  = var.net_hub_project_id
  network                  = google_compute_network.psc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# The endpoint.
#
# The address is GLOBAL and INTERNAL, and must sit outside every subnet range:
# "can't be within the range of subnets configured in the VPC network". That is
# why endpoint_ip is not carved out of subnet_cidr - it is a separate address
# in the same private space, reserved for this and nothing else.
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "psc" {
  name         = "psc-apis-endpoint-ip"
  project      = var.net_hub_project_id
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = var.endpoint_ip
  network      = google_compute_network.psc.id
}

# target is "all-apis" or "vpc-sc" and nothing else. load_balancing_scheme is
# deliberately empty: a PSC forwarding rule is not a load balancer, and the
# provider rejects a scheme here.
#
# The name is capped at 20 characters for this kind of forwarding rule, which
# is shorter than the convention the rest of this lab uses.
resource "google_compute_global_forwarding_rule" "psc" {
  name                  = "psc-apis"
  project               = var.net_hub_project_id
  target                = "all-apis"
  network               = google_compute_network.psc.id
  ip_address            = google_compute_global_address.psc.id
  load_balancing_scheme = ""

  labels = local.labels
}

# ---------------------------------------------------------------------------
# One client with nothing of its own: no external IP, no NAT.
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "iap_ssh" {
  name    = "psc-lab-allow-iap-ssh"
  project = var.net_hub_project_id
  network = google_compute_network.psc.name

  # IAP's TCP forwarding range. The VM has no public address, so this is the
  # only way in, and it is not "allow SSH from anywhere".
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_instance" "probe" {
  name         = "psc-probe"
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

  # No access_config block, so no external IP. That is what makes both halves
  # of this comparison necessary in the first place.
  network_interface {
    subnetwork = google_compute_subnetwork.psc.id
  }

  metadata = local.os_policy_metadata
}

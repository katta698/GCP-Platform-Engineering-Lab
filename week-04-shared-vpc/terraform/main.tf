/*
 * Week 04 — Shared VPC hub-and-spoke. The first week anything runs.
 *
 * Weeks 01 to 03 built control plane: a hierarchy, a CI identity, and the rules
 * the organization refuses to break. All three carried a $0 cost note because
 * nothing existed to bill. This week puts a workload inside that structure.
 *
 * It was Week 12 until 2026-09-03. It moved for a dependency the original
 * ordering had backwards: Week 03 left three compute constraints in dry run —
 * requireOsLogin, blockProjectSshKeys, disableSerialPortAccess — and a dry-run
 * policy only logs when it would have denied a REQUEST. With no Compute Engine
 * resource anywhere in the organization there were no requests to evaluate, so
 * those three could never be promoted on evidence. This week creates the first
 * thing they can refuse.
 *
 * The shape: one host project owning the network, one service project owning the
 * workload, and nothing owning both.
 */

# ---------------------------------------------------------------------------
# APIs
#
# compute on the host for the network itself. On the service project, compute
# again — a service project attached to a Shared VPC still needs the API enabled
# to place instances, even though it owns no network.
# ---------------------------------------------------------------------------

resource "google_project_service" "host" {
  for_each = toset([
    "compute.googleapis.com",
    "oslogin.googleapis.com",
    # Needed because this project is the provider's quota project. Every call
    # this configuration makes is attributed here, including the Resource
    # Manager reads behind the folder lookups — so the host project needs APIs
    # enabled that it does not itself use. Enabling it is a chicken-and-egg:
    # the call that enables it is itself attributed here, so the very first
    # enablement had to be done by hand. It is declared anyway, so a rebuild
    # does not depend on someone remembering.
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbilling.googleapis.com",
  ])

  project            = var.host_project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Where the spoke goes
#
# Resolved by display name at plan time, same as Week 03. Folder IDs are not
# secrets but they are values that rot the first time the hierarchy is rebuilt,
# and a name survives that.
# ---------------------------------------------------------------------------

data "google_folders" "root" {
  parent_id = "organizations/${var.org_id}"
}

locals {
  workloads_folder = one([
    for f in data.google_folders.root.folders : f.name
    if f.display_name == "workloads"
  ])
}

data "google_folders" "workloads" {
  parent_id = local.workloads_folder
}

locals {
  dev_folder = one([
    for f in data.google_folders.workloads.folders : f.name
    if f.display_name == "dev"
  ])
}

# ---------------------------------------------------------------------------
# The network
#
# auto_create_subnetworks = false, and this is the whole argument for custom
# mode. An auto-mode VPC creates a subnet in EVERY region Google has, now and in
# every region added later, each with a range you did not choose. That is a
# network whose address plan is decided by Google's expansion schedule.
#
# Custom mode means the only ranges that exist are the ones written down here.
# ---------------------------------------------------------------------------

resource "google_compute_network" "hub" {
  project                 = var.host_project_id
  name                    = "hub"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  description = "Shared VPC hub. Owns all addressing for the organization; service projects consume subnets and own none."

  depends_on = [google_project_service.host]
}

# Private Google Access is on, and without it a VM with no external IP cannot
# reach Google APIs at all — not Cloud Storage, not Logging, not the OS Login
# metadata it needs to authenticate a session. The instance below deliberately
# has no external address, so this setting is what keeps it functional rather
# than merely reachable-by-nothing.
#
# Flow logs are on for dev on purpose. Week 18 is network observability, and a
# subnet that starts logging on the day it is created has history by then;
# switching them on later leaves a gap exactly where the interesting traffic was.
resource "google_compute_subnetwork" "dev" {
  project       = var.host_project_id
  name          = "dev-${var.region}"
  region        = var.region
  network       = google_compute_network.hub.id
  ip_cidr_range = var.subnet_dev_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Created now and attached to nothing. Reserving the range is the point: address
# plans are decided once, and a prod subnet allocated in a hurry six months from
# now takes whatever is free rather than what was intended.
resource "google_compute_subnetwork" "prod" {
  project       = var.host_project_id
  name          = "prod-${var.region}"
  region        = var.region
  network       = google_compute_network.hub.id
  ip_cidr_range = var.subnet_prod_cidr

  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# Shared VPC
#
# Two resources, and the split matters. Host enablement designates the project
# as one that can lend its network. Attachment is per service project, and is
# what actually permits one to use it. A host with no attachments lends nothing.
# ---------------------------------------------------------------------------

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id

  depends_on = [google_compute_network.hub]
}

# ---------------------------------------------------------------------------
# The spoke
#
# A project per workload, under workloads/dev. Projects are free in Google Cloud
# and are the unit that IAM, quota and deletion all operate on, so rationing
# them the way AWS accounts are rationed concentrates blast radius exactly where
# the hierarchy was meant to separate it.
# ---------------------------------------------------------------------------

resource "google_project" "service" {
  name       = "Dev App 01"
  project_id = var.service_project_id
  folder_id  = local.dev_folder

  billing_account = var.billing_account

  # Same reasoning as every project this lab creates. The default network is a
  # full VPC with permissive firewall rules that nobody asked for, and in a
  # service project it is worse than useless: the project is about to consume a
  # Shared VPC subnet, so a second network exists only to be mistaken for the
  # real one.
  auto_create_network = false

  labels = {
    week       = "04"
    env        = "dev"
    managed-by = "terraform"
  }
}

resource "google_project_service" "service" {
  for_each = toset([
    "compute.googleapis.com",
    "oslogin.googleapis.com",
  ])

  project            = google_project.service.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_shared_vpc_service_project" "dev_app" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = google_project.service.project_id

  depends_on = [google_project_service.service]
}

# ---------------------------------------------------------------------------
# Who may use which subnet
#
# Granted on the SUBNET, not the project. This is the control that makes Shared
# VPC worth using: networkUser at the host project level lets a service project
# place resources in any subnet the host owns, including prod. Scoped to one
# subnet, dev can use dev and cannot see prod.
#
# Two members, and missing either one breaks a different thing. The service
# project's Compute service agent places the instance; the API service agent
# performs operations on the project's behalf. Google's own Shared VPC
# documentation lists both, and an instance creation that fails with a vague
# permission error is usually the second one missing.
# ---------------------------------------------------------------------------

resource "google_compute_subnetwork_iam_member" "dev_network_user" {
  # A map with STATIC keys, not a set. Terraform builds the resource addresses
  # from for_each keys during plan, and the project number is only known after
  # apply — so a set of these strings makes the addresses themselves unknown and
  # the plan refuses outright. Keys that are fixed and values that are not is the
  # shape that works, and it also means the resource addresses stay readable
  # instead of being an email address.
  for_each = {
    cloudservices = "serviceAccount:${google_project.service.number}@cloudservices.gserviceaccount.com"
    compute_agent = "serviceAccount:service-${google_project.service.number}@compute-system.iam.gserviceaccount.com"
  }

  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.dev.name
  role       = "roles/compute.networkUser"
  member     = each.value

  depends_on = [google_compute_shared_vpc_service_project.dev_app]
}

# ---------------------------------------------------------------------------
# Hierarchical firewall policy
#
# Attached to the workloads folder, so it governs every project beneath it —
# including projects that do not exist yet, which is the property that makes it
# different from VPC firewall rules. A VPC firewall rule protects one network. A
# hierarchical policy protects a branch of the hierarchy.
#
# Evaluation order is worth knowing before writing one: hierarchical policies are
# evaluated BEFORE any VPC firewall rule, and an `allow` or `deny` here is final.
# `goto_next` is what hands the decision down to the next level. A policy written
# entirely in allow/deny at the top of the hierarchy takes every firewall
# decision in the organization away from the teams below it.
#
# Cloud NGFW is the product name as of 2026; this is not a legacy API. VPC
# firewall rules are also NOT deprecated — the two coexist, and the reference
# documentation recommends neither over the other. Checked 2026-09-11, because
# the opposite is a plausible thing to assume.
# ---------------------------------------------------------------------------

resource "google_compute_firewall_policy" "workloads" {
  parent      = local.workloads_folder
  short_name  = "workloads-baseline"
  description = "Baseline ingress controls for every project under workloads. Evaluated before any VPC firewall rule."
}

# IAP's TCP forwarding range. This is the one ingress path deliberately left
# open, and it is the reason the instance below needs no external IP and no
# bastion: IAP brokers the connection, authenticates it against IAM, and logs it.
# 35.235.240.0/20 is Google's fixed range for this and is documented, not guessed.
resource "google_compute_firewall_policy_rule" "allow_iap_ssh" {
  firewall_policy = google_compute_firewall_policy.workloads.id
  priority        = 1000
  direction       = "INGRESS"
  action          = "allow"
  enable_logging  = true
  description     = "SSH via Identity-Aware Proxy only. No bastion, no public address."

  match {
    src_ip_ranges = ["35.235.240.0/20"]
    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["22"]
    }
  }
}

# Everything else from the internet is refused, at the folder, before any VPC
# rule is consulted. Logging is on: a deny that nobody can see is a deny you
# cannot debug, and the first question when something cannot connect is always
# whether this rule was the one that stopped it.
resource "google_compute_firewall_policy_rule" "deny_public_ingress" {
  firewall_policy = google_compute_firewall_policy.workloads.id
  priority        = 65000
  direction       = "INGRESS"
  action          = "deny"
  enable_logging  = true
  description     = "Default-deny public ingress for everything under workloads."

  match {
    src_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_firewall_policy_association" "workloads" {
  name              = "workloads-baseline"
  attachment_target = local.workloads_folder
  firewall_policy   = google_compute_firewall_policy.workloads.id
}

# ---------------------------------------------------------------------------
# The instance — and the reason this week exists at this point in the roadmap
#
# e2-micro, us-central1, pd-standard, no external IP. Every one of those is a
# cost decision, not a preference:
#
#   e2-micro          the only machine type in the Always Free tier
#   us-central1       free tier covers us-west1, us-central1, us-east1 only
#   pd-standard       the free 30 GB-month allowance is STANDARD disk;
#                     pd-balanced, which is the default, is billed from the
#                     first byte
#   no external IP    external IPv4 addresses are billed per hour whether or not
#                     traffic flows, and are not in the free tier
#
# Getting any one of those wrong turns a free week into a billed one, quietly.
#
# The metadata block is the part Week 03 has been waiting for. Those three
# constraints are all evaluated against instance metadata, so this instance is
# the first request in the organization they have ever had to judge.
# ---------------------------------------------------------------------------

resource "google_compute_instance" "dev_app" {
  project      = google_project.service.project_id
  name         = "dev-app-01"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork         = google_compute_subnetwork.dev.id
    subnetwork_project = var.host_project_id
    # No access_config block. That is what withholds an external IP; an empty
    # access_config would request an ephemeral one and bill for it.
  }

  # enable-oslogin true satisfies compute.managed.requireOsLogin, which is in dry
  # run at the organization. Setting it deliberately means this instance complies
  # with a constraint that is not yet enforcing — the point of dry run is to find
  # out what would break, and a compliant instance proves the constraint is
  # satisfiable before it starts refusing anything.
  metadata = {
    enable-oslogin = "TRUE"
  }

  labels = {
    week       = "04"
    env        = "dev"
    managed-by = "terraform"
  }

  depends_on = [
    google_compute_subnetwork_iam_member.dev_network_user,
    google_project_service.service,
  ]
}

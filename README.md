# GCP Platform Engineering Lab

**Building production-grade Google Cloud infrastructure from scratch, one week at a time.**

> 14 years as a DBA → moving into cloud architecture.
> Every week: real code, real bugs, real fixes. No tutorials. No sandboxes.

Sister repo to [AWS-Platform-Engineering-Lab](https://github.com/katta698/AWS-Platform-Engineering-Lab).
Same discipline, different cloud — and designed around Google Cloud's own
primitives rather than translated service-by-service from AWS.

Write-ups for each week go to **[jayanthkatta.com](https://jayanthkatta.com)**.

---

## Start here: why folders, and why so many projects

The instinct coming from AWS is that a governance account and a workload account
become a governance project and a workload project. That mapping is wrong, and
following it fights the platform.

An AWS account is heavyweight and slow to create, so you ration them. A Google
Cloud **project is free, created in seconds, and is the unit that owns IAM,
quota, API enablement and billing attribution**. Rationing projects means every
workload shares one IAM surface and one quota pool — exactly what an account
split is supposed to prevent.

**The account split maps onto folders. Projects multiply underneath.**

```
Organization
├── platform                      ← governance / hub
│   ├── network-hub               Shared VPC host — owns every subnet
│   ├── logging                   log sinks, BigQuery datasets
│   └── security                  KMS keyrings, Secret Manager
└── workloads
    ├── dev                       one project per lab week
    └── prod
```

Two Google Cloud behaviours drive this, and neither has an AWS counterpart:

**IAM inherits downward.** A role granted on a folder applies to every project
beneath it — including projects that do not exist yet. In AWS, a role in one
account grants nothing in another. This makes folder-level bindings powerful and
rare; you stop repeating them per project.

**Billing is orthogonal to the hierarchy.** The billing account is not a node in
the tree. One billing account funds projects in any folder, and moving a project
between folders does not change who pays. Cost separation comes from per-project
budgets and labels, not from structure.

The platform projects are split three ways by blast radius. Whoever can rotate a
KMS key should not thereby be able to rewrite the network. Projects cost nothing,
so the correct separation is free.

---

## Built so far

| | |
|---|---|
| **Organization** | Cloud Identity on a domain I own — folders and org policy do not exist without one |
| **Seed project** | Holds the lab's Terraform identity |
| **State** | HCP Terraform, one workspace per week, alongside the AWS lab |
| **Week 01** | 4 folders, 3 platform projects, reusable project-factory module |

A few things worth knowing if you are doing this yourself:

- Folders create in **11–12 seconds**. Projects take **3–5½ minutes**. Plan around it.
- `auto_create_network = false` on every project. The default network ships with
  permissive firewall rules nobody chose.
- Every project enables only the APIs it needs — 2 or 3 each, not the 38 that
  accumulate in a long-lived personal project.
- Verifying a domain does **not** create the organization. It appears when a user
  from that domain first signs in to the Cloud console and accepts the terms.
- `gcloud organizations list` returning zero does not mean there is no
  organization. It queries the v3 API, which only returns orgs you hold
  `resourcemanager.organizations.get` on. A new super admin holds nothing until
  they grant themselves Organization Administrator.

---

## Roadmap

### Phase 1 — Foundations and governance (Weeks 1–6)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| [01](./week-01-gcp-landing-zone) | Landing zone: folders, projects, remote state | Resource Manager, Terraform, HCP | ✅ Complete |
| 02 | Org policy and guardrails | Organization Policy Service, custom constraints | 📅 Planned |
| 03 | Project vending machine | Cloud Build, Service Usage, Resource Manager | 📅 Planned |
| 04 | Billing export and budget alerts | Cloud Billing, BigQuery, Budgets, Pub/Sub | 📅 Planned |
| 05 | Terraform CI/CD, keyless | Cloud Build, Workload Identity Federation | 📅 Planned |
| 06 | Resource hierarchy audit and drift | Cloud Asset Inventory, asset feeds, BigQuery | 📅 Planned |

### Phase 2 — Identity and access (Weeks 7–11)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 07 | IAM: roles, conditions, deny policies | Cloud IAM, IAM Conditions, Deny Policies | 📅 Planned |
| 08 | Service accounts and Workload Identity Federation | WIF, keyless GitHub Actions auth | 📅 Planned |
| 09 | Cloud Identity and group-based access | Cloud Identity, Google Groups | 📅 Planned |
| 10 | Privileged access and just-in-time elevation | Privileged Access Manager, IAM Recommender | 📅 Planned |
| 11 | Secret management | Secret Manager, Cloud KMS, CMEK, rotation | 📅 Planned |

### Phase 3 — Networking (Weeks 12–19)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 12 | Shared VPC hub-and-spoke | Shared VPC, hierarchical firewall policies | 📅 Planned |
| 13 | Hybrid connectivity | HA VPN, Cloud Router, BGP | 📅 Planned |
| 14 | Private Service Connect | PSC endpoints, Private Google Access | 📅 Planned |
| 15 | Global load balancing | Global external ALB, Cloud CDN, Cloud Armor | 📅 Planned |
| 16 | Cloud NAT and egress control | Cloud NAT, Secure Web Proxy | 📅 Planned |
| 17 | Cloud DNS: private and split-horizon | Cloud DNS, peering, forwarding | 📅 Planned |
| 18 | Network observability | VPC Flow Logs, Network Intelligence Center | 📅 Planned |
| 19 | VPC Service Controls perimeter | VPC-SC, Access Context Manager | 📅 Planned |

### Phase 4 — Compute (Weeks 20–25)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 20 | Compute Engine self-service | Compute Engine, MIGs, custom images | 📅 Planned |
| 21 | Autoscaling and load-balanced fleet | Regional MIGs, autoscaler, health checks | 📅 Planned |
| 22 | OS patch management at fleet scale | VM Manager, OS Config, OS Inventory | 📅 Planned |
| 23 | Spot VMs and cost-optimised compute | Spot VMs, CUDs, rightsizing recommender | 📅 Planned |
| 24 | Confidential and Shielded VMs | Shielded VM, Confidential Computing | 📅 Planned |
| 25 | Golden image pipeline | Cloud Build, Packer, Artifact Registry | 📅 Planned |

### Phase 5 — Containers and Kubernetes (Weeks 26–31)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 26 | GKE Autopilot self-service | GKE Autopilot, Workload Identity | 📅 Planned |
| 27 | GitOps with Config Sync | Config Sync, Policy Controller, fleets | 📅 Planned |
| 28 | Cloud Run services and jobs | Cloud Run, traffic splitting | 📅 Planned |
| 29 | Container supply chain security | Artifact Analysis, Binary Authorization | 📅 Planned |
| 30 | Service mesh | Cloud Service Mesh, mTLS | 📅 Planned |
| 31 | Multi-cluster and fleet ingress | Multi Cluster Ingress, Gateway API | 📅 Planned |

### Phases 6–12 — Storage, data, serverless, security, operations, FinOps, DR (Weeks 32–53)

Storage lifecycle and Filestore · Cloud SQL, AlloyDB, Spanner, BigQuery ·
Pub/Sub and Dataflow · Eventarc and Workflows · Security Command Center and
Cloud Armor · Cloud Monitoring, SLOs and centralised logging · committed use
discounts and showback · multi-region failover.

---

## Repo layout

```
├── scripts/                    tooling shared across weeks
├── terraform/bootstrap/        one-time: seed project
└── week-NN-<topic>/
    ├── README.md               what it does, how to run it, what it costs
    ├── terraform/
    ├── scripts/                deploy, validate, cleanup
    └── docs/blog/screenshots/
```

## Running any week

Terraform reads Application Default Credentials, not your `gcloud auth login`
session — they are separate credential stores, and this catches people out:

```bash
gcloud auth application-default login
```

Then, in the week's `terraform/` directory:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Fill it in — organization ID, billing account, project IDs. `terraform.tfvars` is
gitignored and should stay that way. Then:

```bash
terraform init && terraform plan
```

Read the plan before applying. Every week's README opens with a cost note saying
what runs continuously and what the cleanup script removes.

## A note on secrets

No organization ID, billing account ID, project number or service account key
appears anywhere in this repo. Screenshots are redacted programmatically before
they are written to disk — see [`scripts/screenshots/capture_gcp.py`](./scripts/screenshots/capture_gcp.py),
which refuses to save a file if an identifier survives redaction, or if the page
turns out to be a sign-in screen.

There are no service account keys in this lab at all. CI authenticates through
Workload Identity Federation from Week 05.

## Licence

MIT. Take what is useful.

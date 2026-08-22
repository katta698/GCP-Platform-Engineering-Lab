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
| 13 | Hybrid and cross-cloud connectivity | HA VPN, Cloud Router, BGP, Cross-Cloud Network | 📅 Planned |
| 14 | Private Service Connect | PSC endpoints, Private Google Access | 📅 Planned |
| 15 | Global load balancing | Global external ALB, Cloud CDN, Cloud Armor | 📅 Planned |
| 16 | Cloud NAT and egress control | Cloud NAT, Secure Web Proxy | 📅 Planned |
| 17 | Cloud DNS: private and split-horizon | Cloud DNS, peering, forwarding | 📅 Planned |
| 18 | Network observability | VPC Flow Logs, Network Intelligence Center, Cloud Network Insights | 📅 Planned |
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
| 30 | Ambient networking — mesh without sidecars | Ambient data plane for GKE and Cloud Run, zero-trust, mTLS | 📅 Planned |
| 31 | Multi-cluster Gateway API | GKE fleets, multi-cluster Gateway, GatewayClass | 📅 Planned |

### Phase 6 — Storage (Weeks 32–35)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 32 | Cloud Storage lifecycle and tiering | Storage classes, Autoclass, lifecycle, retention | 📅 Planned |
| 33 | Block and file: Hyperdisk, Filestore, Managed Lustre | Hyperdisk, Filestore, Managed Lustre, snapshot schedules | 📅 Planned |
| 34 | Backup and restore automation | Backup and DR Service, snapshot policies | 📅 Planned |
| 35 | Data transfer and migration | Storage Transfer Service, Transfer Appliance | 📅 Planned |

### Phase 7 — Databases and data platform (Weeks 36–42)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 36 | Cloud SQL self-service platform | Cloud SQL, HA, read replicas, Auth Proxy, IAM auth | 📅 Planned |
| 37 | AlloyDB and the lakehouse boundary | AlloyDB, columnar engine, live Iceberg/BigQuery reads, reverse ETL | 📅 Planned |
| 38 | Spanner: global consistency and columnar scans | Spanner, multi-region configs, Columnar Engine, TrueTime | 📅 Planned |
| 39 | BigQuery for variable workloads | Partitioning, clustering, fluid scaling, reservations | 📅 Planned |
| 40 | Streaming pipelines | Pub/Sub, Dataflow, BigQuery streaming, continuous queries | 📅 Planned |
| 41 | Database Migration Service | DMS, homogeneous and heterogeneous migration, CDC | 📅 Planned |
| 42 | Firestore and Memorystore | Firestore, Memorystore for Valkey | 📅 Planned |

### Phase 8 — Serverless and integration (Weeks 43–45)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 43 | Event-driven platform | Eventarc, Pub/Sub, Cloud Run functions | 📅 Planned |
| 44 | Workflows and orchestration | Workflows, Cloud Scheduler, Cloud Tasks | 📅 Planned |
| 45 | API management | API Gateway, Apigee, Cloud Endpoints | 📅 Planned |

### Phase 9 — Security and compliance (Weeks 46–48)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 46 | Security Command Center | SCC findings, mute rules, auto-remediation | 📅 Planned |
| 47 | Cloud Armor and edge protection | Cloud Armor policies, rate limiting, adaptive protection | 📅 Planned |
| 48 | Audit logging, forensics and sovereignty | Cloud Audit Logs, log sinks, Confidential External Key Management | 📅 Planned |

### Phase 10 — Observability and operations (Weeks 49–51)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 49 | Cloud Monitoring and SLOs | SLOs, error budgets, alerting policies | 📅 Planned |
| 50 | Centralised logging | Log Router, sinks, log buckets, Log Analytics | 📅 Planned |
| 51 | Tracing and profiling | Cloud Trace, Cloud Profiler, OpenTelemetry | 📅 Planned |

### Phases 11–12 — FinOps and reliability (Weeks 52–53)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 52 | FinOps: CUDs, recommender, showback | Billing BigQuery export, Recommender, Looker Studio | 📅 Planned |
| 53 | Disaster recovery and chaos | Multi-region failover, Backup and DR, fault injection | 📅 Planned |

### Phase 13 — AI and agent platform (Weeks 54–58)

The reason this phase exists: a platform-engineering lab running into 2027 that
never touches agent infrastructure is describing a cloud that no longer matches
the one people are being asked to run. Google's 2026 platform reorganised around
agents — Vertex AI itself was folded into the **Gemini Enterprise Agent
Platform** — and the interesting problems are the platform ones: identity for
non-human callers, egress governance, isolation, and cost attribution for
workloads whose usage is inherently variable.

Treated as infrastructure, not as model demos.

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| 54 | Agent platform foundations | Gemini Enterprise Agent Platform, Agent Runtime, IAM for agents | 📅 Planned |
| 55 | Agent Gateway: governing agent traffic | Agent Gateway, MCP and A2A protocols, egress policy | 📅 Planned |
| 56 | Isolating untrusted agent workloads | GKE Agent Sandbox, Workload Identity, network policy | 📅 Planned |
| 57 | Grounding agents in governed data | BigQuery Graph, AI.PARSE_DOCUMENT, VPC-SC around the data plane | 📅 Planned |
| 58 | Agent observability and cost control | Per-second billing exposure, tracing, budget guardrails | 📅 Planned |

Week 55 is the direct counterpart to Week 17 of the AWS lab, which builds an MCP
server over that lab's own operational data. Same problem — making a platform
agent-consumable — approached from the governance side rather than the server
side.

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

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
| **Weeks 01–06** | Hierarchy, keyless CI, org-policy guardrails, Shared VPC, project factory, billing export |
| **Weeks 07–12** | Asset inventory, deny policies, SA lifecycle, group access, just-in-time elevation, CMEK and rotation |
| **Detail** | Per-week sections below — story, what it builds, resource count, lessons |

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
| [Week 01](./week-01-gcp-landing-zone) | Landing zone: folders, projects, state | Resource Manager, HCP | ✅ Complete |
| [Week 02](./week-02-keyless-ci) | Keyless CI with Workload Identity | WIF, HCP dynamic credentials | ✅ Complete |
| [Week 03](./week-03-org-policy-guardrails) | Org policy guardrails and dry run | Org Policy, custom constraints | ✅ Complete |
| [Week 04](./week-04-shared-vpc) | Shared VPC hub and spoke | Shared VPC, Cloud NGFW | ✅ Complete |
| [Week 05](./week-05-project-factory) | Project factory and naming constraint | Tags, custom constraints | ✅ Complete |
| [Week 06](./week-06-billing-export) | Billing export and programmatic budget alerts | Billing, BigQuery, Budgets, Pub/Sub | ✅ Complete |
| [Week 07](./week-07-asset-inventory) | Resource hierarchy audit | Asset Inventory, Pub/Sub, BigQuery | ✅ Complete |

**Why Shared VPC moved from Week 12 to Week 04.** Re-sequenced 2026-09-03, and
not for variety — for a dependency the original ordering had backwards.

Week 03 left three constraints in dry run: `compute.managed.requireOsLogin`,
`compute.managed.blockProjectSshKeys` and
`compute.managed.disableSerialPortAccess`. A dry-run policy is evaluated on every
request and logged when it would have denied. **With no Compute Engine resource
in the organization, there are no requests to evaluate**, so those three generate
no violations, and a constraint cannot be promoted out of dry run on no evidence.
The original ordering left them parked until Week 12.

The move costs nothing structurally. Shared VPC's prerequisite is a host project,
and `katta698-gcp-net-hub` has existed since Week 01 with `compute`, `dns`,
`networkmanagement` and `oslogin` already enabled and no VPC in it — Week 01 set
`auto_create_network = false`, so the permissive default network never existed.
Nothing in the project factory, billing export or asset inventory weeks is a
prerequisite for a VPC, and the one IAM grant Shared VPC needs
(`roles/compute.networkUser`) is a single binding, not a week.

It is also the first week with a **non-zero cost note**. Weeks 01–03 created no
billable resource; a VM and any egress do. That is a real change in what the lab
is doing, and it should not be nine weeks away.

**Why CI comes second.** Two properties of Google Cloud decide this, and neither
is a matter of taste.

Organization policy is evaluated **at resource creation**. A constraint added
after a project exists does not retroactively fix that project. So every week
built before a pipeline exists is a week of resources created by hand, outside
review, that later constraints will not clean up.

And the usual failure mode in Google Cloud CI — a **service account key** in a
file or a CI variable — is already impossible here, without anyone deciding it.
Every organization created on or after **3 May 2024** inherits Google's security
baseline constraints, and this one arrived with seven already enforced,
including `iam.managed.disableServiceAccountKeyCreation` and
`iam.disableServiceAccountKeyUpload`.

So the week is not "ban the shortcut, then build the alternative". The shortcut
was banned before I arrived. The week is: find out what the platform has already
decided on your behalf, prove it by trying to create a key and watching it fail,
and then build the only path left — Workload Identity Federation, where HCP
Terraform mints an OIDC token per run and Google exchanges it for a short-lived
credential that never touches disk.

That is a more useful lesson than the one I set out to write, and it is only
visible if you look at the org policy before assuming you have to write it.

### Phase 2 — Identity and access (Weeks 8–12)

Shifted by one, and improved by it. These weeks are about who may act on
resources; running them after Week 04 means there are resources to act on, so
every grant can be demonstrated against something real rather than described.

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| [Week 08](./week-08-iam-deny) | IAM deny policies and custom roles | Deny policies, Troubleshooter v3 | ✅ Complete |
| [Week 09](./week-09-sa-lifecycle) | Service account lifecycle | Activity Analyzer, Org Policy | ✅ Complete |
| [Week 10](./week-10-group-access) | Group-based access control | Cloud Identity, Google Groups | ✅ Complete |
| [Week 11](./week-11-jit-access) | Privileged access and just-in-time elevation | Privileged Access Manager | ✅ Complete |
| [Week 12](./week-12-secret-management) | CMEK, and the rotation that only notifies | Secret Manager, Cloud KMS, Pub/Sub, Cloud Run functions | ✅ Complete |

### Phase 3 — Networking (Weeks 13–19)

Shared VPC has moved out of this phase to Week 04; see the note above. What
remains here is everything that needs a VPC to already exist.

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| [Week 13](./week-13-hybrid-connectivity) | HA VPN and BGP between two VPCs | HA VPN, Cloud Router, BGP | ✅ Complete |
| Week 14 | Private Service Connect | PSC endpoints, Private Google Access | 📅 Planned |
| Week 15 | Global load balancing | Global external ALB, Cloud CDN, Cloud Armor | 📅 Planned |
| Week 16 | Cloud NAT and egress control | Cloud NAT, Secure Web Proxy | 📅 Planned |
| Week 17 | Cloud DNS: private and split-horizon | Cloud DNS, peering, forwarding | 📅 Planned |
| Week 18 | Network observability | VPC Flow Logs, Network Intelligence Center, Cloud Network Insights | 📅 Planned |
| Week 19 | VPC Service Controls perimeter | VPC-SC, Access Context Manager | 📅 Planned |

### Phase 4 — Compute (Weeks 20–25)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 20 | Compute Engine self-service | Compute Engine, MIGs, custom images | 📅 Planned |
| Week 21 | Autoscaling and load-balanced fleet | Regional MIGs, autoscaler, health checks | 📅 Planned |
| Week 22 | OS patch management at fleet scale | VM Manager, OS Config, OS Inventory | 📅 Planned |
| Week 23 | Spot VMs and cost-optimised compute | Spot VMs, CUDs, rightsizing recommender | 📅 Planned |
| Week 24 | Confidential and Shielded VMs | Shielded VM, Confidential Computing | 📅 Planned |
| Week 25 | Golden image pipeline | Cloud Build, Packer, Artifact Registry | 📅 Planned |

### Phase 5 — Containers and Kubernetes (Weeks 26–31)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 26 | GKE Autopilot self-service | GKE Autopilot, Workload Identity | 📅 Planned |
| Week 27 | GitOps with Config Sync | Config Sync, Policy Controller, fleets | 📅 Planned |
| Week 28 | Cloud Run services and jobs | Cloud Run, traffic splitting | 📅 Planned |
| Week 29 | Container supply chain security | Artifact Analysis, Binary Authorization | 📅 Planned |
| Week 30 | Ambient networking — mesh without sidecars | Ambient data plane for GKE and Cloud Run, zero-trust, mTLS | 📅 Planned |
| Week 31 | Multi-cluster Gateway API | GKE fleets, multi-cluster Gateway, GatewayClass | 📅 Planned |

### Phase 6 — Storage (Weeks 32–35)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 32 | Cloud Storage lifecycle and tiering | Storage classes, Autoclass, lifecycle, retention | 📅 Planned |
| Week 33 | Block and file: Hyperdisk, Filestore, Managed Lustre | Hyperdisk, Filestore, Managed Lustre, snapshot schedules | 📅 Planned |
| Week 34 | Backup and restore automation | Backup and DR Service, snapshot policies | 📅 Planned |
| Week 35 | Data transfer and migration | Storage Transfer Service, Transfer Appliance | 📅 Planned |

### Phase 7 — Databases and data platform (Weeks 36–42)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 36 | Cloud SQL self-service platform | Cloud SQL, HA, read replicas, Auth Proxy, IAM auth | 📅 Planned |
| Week 37 | AlloyDB and the lakehouse boundary | AlloyDB, columnar engine, live Iceberg/BigQuery reads, reverse ETL | 📅 Planned |
| Week 38 | Spanner: global consistency and columnar scans | Spanner, multi-region configs, Columnar Engine, TrueTime | 📅 Planned |
| Week 39 | BigQuery for variable workloads | Partitioning, clustering, fluid scaling, reservations | 📅 Planned |
| Week 40 | Streaming pipelines | Pub/Sub, Dataflow, BigQuery streaming, continuous queries | 📅 Planned |
| Week 41 | Database Migration Service | DMS, homogeneous and heterogeneous migration, CDC | 📅 Planned |
| Week 42 | Firestore and Memorystore | Firestore, Memorystore for Valkey | 📅 Planned |

### Phase 8 — Serverless and integration (Weeks 43–45)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 43 | Event-driven platform | Eventarc, Pub/Sub, Cloud Run functions | 📅 Planned |
| Week 44 | Workflows and orchestration | Workflows, Cloud Scheduler, Cloud Tasks | 📅 Planned |
| Week 45 | API management | API Gateway, Apigee, Cloud Endpoints | 📅 Planned |

### Phase 9 — Security and compliance (Weeks 46–48)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 46 | Security Command Center | SCC findings, mute rules, auto-remediation | 📅 Planned |
| Week 47 | Cloud Armor and edge protection | Cloud Armor policies, rate limiting, adaptive protection | 📅 Planned |
| Week 48 | Audit logging, forensics and sovereignty | Cloud Audit Logs, log sinks, Confidential External Key Management | 📅 Planned |

### Phase 10 — Observability and operations (Weeks 49–51)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 49 | Cloud Monitoring and SLOs | SLOs, error budgets, alerting policies | 📅 Planned |
| Week 50 | Centralised logging | Log Router, sinks, log buckets, Log Analytics | 📅 Planned |
| Week 51 | Tracing and profiling | Cloud Trace, Cloud Profiler, OpenTelemetry | 📅 Planned |

### Phases 11–12 — FinOps and reliability (Weeks 52–53)

| Week | Project | Key services | Status |
|------|---------|--------------|--------|
| Week 52 | FinOps: CUDs, recommender, showback | Billing BigQuery export, Recommender, Looker Studio | 📅 Planned |
| Week 53 | Disaster recovery and chaos | Multi-region failover, Backup and DR, fault injection | 📅 Planned |

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
| Week 54 | Agent platform foundations | Gemini Enterprise Agent Platform, Agent Runtime, IAM for agents | 📅 Planned |
| Week 55 | Agent Gateway: governing agent traffic | Agent Gateway, MCP and A2A protocols, egress policy | 📅 Planned |
| Week 56 | Isolating untrusted agent workloads | GKE Agent Sandbox, Workload Identity, network policy | 📅 Planned |
| Week 57 | Grounding agents in governed data | BigQuery Graph, AI.PARSE_DOCUMENT, VPC-SC around the data plane | 📅 Planned |
| Week 58 | Agent observability and cost control | Per-second billing exposure, tracing, budget guardrails | 📅 Planned |

Week 55 is the direct counterpart to Week 17 of the AWS lab, which builds an MCP
server over that lab's own operational data. Same problem — making a platform
agent-consumable — approached from the governance side rather than the server
side.

---

## Beyond week 58 — optional, not committed

The roadmap above runs to 58 because Phase 13 was added after the original plan
was checked against live sources and the whole agent platform turned out to be
missing. Everything below is a list, not a commitment.

### Carried forward — displaced from Year 1, not dropped on merit

| Topic | Why it moved |
|---|---|
| Cross-cloud networking to AWS | Week 13 builds HA VPN and BGP against a second VPC. The AWS peer needs the other lab's side built in step, so it waits for a week both windows can run together. |
| Autokey for CMEK | Week 12 named it and did not build it. Autokey creates key rings on demand, which is a different governance story from holding one key, and it deserves its own week rather than a paragraph. |
| Multi-party approval for PAM | Week 11 used a single human approver because multi-party approval needs Security Command Center Premium. The control is real; the tier is not activated here. |
| IAM Recommender | Week 11 found it needs SCC Premium for anything beyond basic roles. Every grant in this lab is predefined, so the free tier reports nothing. |

### Candidate themes for Weeks 59+

- Config Connector and Crossplane — managing Google Cloud from inside Kubernetes
- Backup and DR orchestration across regions, measured rather than assumed
- Sovereign and assured workloads controls
- Chaos engineering against the hierarchy: what actually breaks when a folder's policy changes
- Cost attribution for shared infrastructure, which Week 06's export makes answerable

---

## What Gets Built Each Week

Every week produces three things: a deployed lab, a published write-up, and a
runbook. The lab is real infrastructure in a real organization, built with
Terraform and applied through HCP Terraform with no stored credentials. The
write-up goes to jayanthkatta.com and carries measured results rather than
documentation summaries — if a number appears in a post it came from this
deployment. The runbook is `LAB.md` in the week's folder, so the post does not
have to be one.

Most weeks are destroyed the same day. The cost note at the top of each week's
README says what runs continuously, what teardown removes, and the monthly
figure if it were left up.

---

## Week-by-week

What each completed week actually built, and what it taught. Resource counts
are `resource` blocks in that week's Terraform including modules, reproducible
with:

```bash
find week-NN-* -name '*.tf' -not -path '*/.terraform/*' | xargs grep -h '^resource "' | wc -l
```

---

## Week 01 — Landing zone: folders, projects, state

**The story:** Start from nothing — no organization, no folders, no projects — and end with a hierarchy that every later week hangs off.

**What it builds:**
- Cloud Identity organization on a domain I own
- 4 folders: `platform`, `workloads`, and `dev`/`prod` beneath it
- 3 platform projects: network hub, logging, security
- Reusable project-factory module, `auto_create_network = false` on all of them
- HCP Terraform backend, one workspace per week

**Resources:** 6 blocks + 3 module calls | **Blog:** https://jayanthkatta.com/blog/week-01-gcp-landing-zone/

**Key lessons:**
- Verifying a domain does **not** create the organization. It appears when a user from that domain first signs in to the console and accepts the terms.
- `gcloud organizations list` returning zero does not mean there is no organization — it queries v3, which only returns orgs you hold `resourcemanager.organizations.get` on.
- Folders create in 11–12 seconds. Projects take 3–5½ minutes.

---

## Week 02 — Keyless CI with Workload Identity

**The story:** CI that deploys to Google Cloud without a service account key existing anywhere — because the org's security baseline already made keys impossible.

**What it builds:**
- Workload identity pool and OIDC provider trusting HCP Terraform
- Two service accounts, `tf-plan` and `tf-apply`, split by run phase
- Attribute condition pinning organization, project and workspace prefix
- Project lien on the seed project

**Resources:** 58 blocks — this file accumulates, see below | **Blog:** https://jayanthkatta.com/blog/week-02-keyless-ci/

**Key lessons:**
- The HCP organization's real name is lowercase `katta`. Every UI shows `Katta`; the OIDC token carries the true value and Google's CEL comparison is case-sensitive. The error names no claim.
- `terraform init` creates a missing workspace in HCP's *Default Project*, not the one the rest of the lab lives in.
- `roles/viewer` at the organization cannot read a folder. Basic roles predate the hierarchy; `roles/browser` is what grants it.
- **This week's config is the lab's permission ledger.** Nearly every later week adds grants here, which is why the resource count is high and still rising.

---

## Week 03 — Org policy guardrails and dry run

**The story:** Write four organization policies, run them all in dry run first, and read what they *would* have denied before anything is enforced.

**What it builds:**
- Three managed constraints: OS Login, block project SSH keys, disable serial port
- One custom constraint requiring Terraform labels on buckets
- A folder-level exception for the dev folder
- All four in dry run, promoted on evidence later

**Resources:** 8 | **Blog:** https://jayanthkatta.com/blog/week-03-org-policy-guardrails/

**Key lessons:**
- `gcloud org-policies list` shows what is **set**, not what is **enforced**. A managed constraint can be fully enforced by a Google default that appears in neither `list` nor plain `describe` — only `--effective` reveals it.
- Enforcement lags the write by 75–100s, and un-enforcement by 77–108s. The reverse lag is the dangerous one: disable a guardrail during an incident, see the apply go green, retry, still get refused.
- Dry-run violations land in the **project** audit log, not the organization's. Querying the org stream returns empty without an error.

---

## Week 04 — Shared VPC hub and spoke

**The story:** One project owns the network, another runs the workload, and the workload project never sees a subnet it did not ask for.

**What it builds:**
- Shared VPC host project with a custom-mode VPC
- Two subnets with flow logs and Private Google Access
- Hierarchical firewall policy at the folder — a project cannot opt out
- Service project attachment, one e2-micro with no external IP, IAP for SSH

**Resources:** 14 | **Blog:** https://jayanthkatta.com/blog/week-04-shared-vpc/

**Key lessons:**
- Creating a firewall policy and **attaching** it are different roles. `orgSecurityPolicyAdmin` has `firewallPolicies.create/update/use` but not `organizations.setFirewallPolicy`.
- `compute.xpnAdmin` cannot be folder-scoped — host enablement is checked at the organization.
- A folder-scoped firewall policy needs a quota project; without it you get `Error 404: The resource 'projects/null' was not found`.
- Billing accounts cap linked projects. This lab hit the limit at five.

---

## Week 05 — Project factory and naming constraint

**The story:** A module that makes the right project, and a custom constraint that refuses the wrong one.

**What it builds:**
- Project-factory module with labels, tags, essential contacts and a lien
- Org-level tag key `environment` with a closed set of values
- Custom constraint on project ID prefix and parent folder, in dry run

**Resources:** 9 blocks + 1 module call | **Blog:** https://jayanthkatta.com/blog/week-05-project-factory/

**Key lessons:**
- A custom constraint on a Project **cannot read that project's labels**. `resource.projectId` and `resource.parent` are accepted; `resource.labels` and `resource.displayName` are rejected with `Error 400: Request has invalid values`, naming nothing.
- `tagAdmin` cannot bind a tag — that is `tagUser`. Same create-versus-attach split as Week 04's firewall policies.
- An enforced constraint can make a resource un-reconcilable with its own config.

---

## Week 06 — Billing export and budget alerts

**The story:** Make the bill queryable in SQL, and make the budget alert reach something that can act on it.

**What it builds:**
- BigQuery pricing export dataset in the logging project
- Budget with a programmatic `all_updates_rule` publishing to Pub/Sub
- A project-scoped org-policy override, and a `time_sleep` that is load-bearing

**Resources:** 7 | **Blog:** https://jayanthkatta.com/blog/week-06-billing-export/

**Key lessons:**
- **The export was already running.** A detailed usage export had been landing unqueried since July. The week's written premise was false — read live state before believing it.
- `Precondition check failed` with no resource, no policy and no `details` array means domain restricted sharing. Cloud Billing writes its own service agent onto the topic, and Week 03's constraint blocked it.
- Org policy *relaxation* propagates as slowly as enforcement. A `time_sleep` of 120s sits between the override and the budget.
- `billing.accounts.getPricing` is in `billing.viewer` and `billing.admin` only — not `billing.user` or `costsManager`.

---

## Week 07 — Resource hierarchy audit

**The story:** Turn the whole organization into a table you can query, then run the audit and see what it says about itself.

**What it builds:**
- Org-level Cloud Asset Inventory feed to Pub/Sub
- BigQuery snapshot export
- Three service-agent grants, because the service writes as itself

**Resources:** 7 | **Blog:** https://jayanthkatta.com/blog/week-07-asset-inventory/

**Key lessons:**
- Cloud Asset Inventory writes to destinations **as itself**. Being project owner on the destination is not enough and never becomes enough.
- No read-only role can read an asset feed. `cloudasset.viewer` lacks `feeds.get`; only `cloudasset.owner` has it, and it also grants create/update/delete.
- The same service gives an excellent error on one destination and `The caller does not have permission` on another.
- The audit found two projects sitting at the org root, and a naming constraint still in dry run that would not have caught either.

---

## Week 08 — IAM deny policies and custom roles

**The story:** A permission that cannot be granted back, and a role that holds exactly what it needs.

**What it builds:**
- IAM deny policy at the organization
- Custom role replacing an over-broad predefined one
- Policy Troubleshooter v3 used to explain each decision

**Resources:** 3 | **Blog:** https://jayanthkatta.com/blog/week-08-iam-deny/

---

## Week 09 — Service account lifecycle

**The story:** Find the service accounts nobody uses, prove they are unused, and disable them without deleting anything.

**What it builds:**
- Two default Compute Engine service accounts disabled with `restore_policy = REVERT`
- `iam.disableServiceAccountKeyCreation` set on the legacy constraint generation

**Resources:** 3 | **Blog:** https://jayanthkatta.com/blog/week-09-sa-lifecycle/

**Key lessons:**
- The two key constraints are enforced on **different generations**. Checking only the legacy name produces a confident, wrong "the rule is off".
- `finops-reader` looked dormant and was not. Measure with `gcloud policy-intelligence query-activity`; never reason about which accounts look idle.
- **Disable, never delete** — and the reason is not reversibility. A deleted SA's email can be reused but IAM tracks an internal unique ID, so old bindings never apply to the replacement.

---

## Week 10 — Group-based access control

**The story:** Put the role on a group, put the identity in the group, and watch access appear and disappear with membership alone.

**What it builds:**
- Cloud Identity group with a folder-level role binding
- A service account that holds nothing directly
- 6 resources, all destroyed the same night

**Resources:** 6 | **Blog:** https://jayanthkatta.com/blog/week-10-group-access/

**Key lessons:**
- `WITH_INITIAL_OWNER` conferred **no ownership**. The apply reported success and left an object nobody could manage.
- Refresh runs as the **plan** identity. Granting `tf-apply` Groups Admin changed nothing.
- `gcloud identity groups search --organization=<ORG>` returns zero **always** — groups are parented to `customers/<id>`. Exit 0, no output, reads exactly like "no groups exist".
- Workspace admin role grants take minutes to take effect, and return a flat 403 in the meantime.

---

## Week 11 — Privileged access and just-in-time elevation

**The story:** Make a privileged role something a principal requests, holds briefly and loses — then measure whether the losing half actually happens.

**What it builds:**
- Privileged Access Manager entitlement on the platform folder
- A subject service account holding nothing
- The PAM service-agent onboarding grant

**Resources:** 5 | **Blog:** https://jayanthkatta.com/blog/week-11-jit-access/

**Key lessons:**
- **Enabling an API is not enabling the feature for a resource.** PAM needs its org-scoped service agent granted `folderServiceAgent` on the folder — which carries `folders.setIamPolicy`.
- 30 minutes is the floor for `max_request_duration`. There is no way to hand someone five minutes.
- **A plan over empty state never authenticates.** The first plan passed while the workspace pointed at the wrong workload identity provider; the apply then failed at token exchange.
- Measured: the binding disappears within ~13s of expiry, across three trials. Published as a range, because two pollers watching the same expiry reported 7s and 13s.

---

## Week 12 — Secret management: CMEK and rotation

**The story:** Put a secret under a key you hold, set it to rotate every hour, and watch the value stay exactly the same.

**What it builds:**
- Cloud KMS key ring and key in `global`, software protection
- Secret with automatic replication and CMEK
- Pub/Sub topic and observer subscription
- A Cloud Run function rotator — the piece Secret Manager does not ship

**Resources:** 23 | **Blog:** https://jayanthkatta.com/blog/week-12-secret-management/

**Key lessons:**
- **Secret Manager "rotation" rotates nothing.** It publishes a `SECRET_ROTATE` message and stops. Measured both ways: version count unmoved with nothing subscribed, moving once ~50 lines of Python were.
- **Every API bills the caller unless told otherwise.** The KMS call was attributed to the seed project, where the pipeline's identity lives, not where the key went.
- CMEK revocation is real but not instant — 70s, 2s and 27s across three trials. Any fixed wait under ~70s will sometimes call a working control broken.
- A key version is billed while **Disabled** and while **Scheduled for destruction**. Only `DESTROYED` stops the meter, and that defaults to 30 days away.
- `terraform destroy` reports success and leaves the key. `DESTROYED` is not `deleted` — the version still blocks the key until an explicit `versions delete`. The key ring deletes only over REST; `gcloud kms keyrings` has no `delete`.

## Week 13 — Hybrid connectivity: HA VPN and BGP

**The story:** Join two VPCs with two IPsec tunnels, then break one and watch BGP route around it without anyone touching a route table.

**What it builds:**
- Two HA VPN gateways, two interfaces each
- Two Cloud Routers on separate private ASNs, 64512 and 64513
- Four tunnel resources, which are the two logical tunnels seen from both ends
- A VM either side, as instruments rather than as the subject

**Resources:** 22 | **Blog:** https://jayanthkatta.com/blog/week-13-hybrid-connectivity/

**Key lessons:**
- **BGP is what makes the HA real.** Routes learned through a dead tunnel were withdrawn in 3.1–3.6s across three trials, and the surviving tunnel carried the prefix throughout. A static route points at a dead tunnel as confidently as a live one.
- **A single active interface carries no SLA.** 99.99% requires two interfaces, two tunnels and two peer addresses; one of each is a supported configuration with no availability promise attached.
- A GCP-to-GCP pair needs **four** tunnel resources for two logical tunnels, and each one bills separately at $0.05/hr. The week cost $1.76, of which $1.72 was tunnels.
- HA VPN tunnels have no enable/disable verb. Disabling the BGP peer is the closest reversible equivalent and exercises the same withdrawal path.
- Classic VPN is **not** deprecated, which is worth saying because every comparison implies it is.

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

---

## Cost Philosophy

Build it, measure it, destroy it. Almost every week in this lab exists for
hours, not months, and the figure that matters is what it cost while it ran —
not the monthly rate a pricing page quotes.

Three rules follow from that:

- **Read cost from the bill, never from a rate card.** Week 06 built a BigQuery
  pricing export for exactly this, and later weeks query it rather than quoting
  published prices.
- **The teardown is part of the week.** `scripts/cleanup.sh` in each folder, and
  a figure check that refuses to destroy anything while a declared screenshot is
  still uncaptured.
- **Name what keeps charging.** Week 12 found that a Cloud KMS key version is
  billed while disabled *and* while scheduled for destruction — teardown reported
  success and the meter kept running. That kind of thing goes in the week's cost
  note, not in a footnote.

A $25/month budget alert covers the whole billing account. It alerts; it does
not cap.

---

## About

14 years as a DBA, moving into cloud architecture. This lab is the Google Cloud
half of that — the AWS and Azure labs run the same discipline on their own
clouds, and the three are deliberately consistent in structure so they read as
one body of work.

Every week is built from Google Cloud's own primitives rather than translated
from another cloud service-by-service. Where a week finds something the
documentation does not say, or says wrongly, that goes in the write-up with the
evidence attached.

- **Blog:** https://jayanthkatta.com
- **AWS lab:** https://github.com/katta698/AWS-Platform-Engineering-Lab

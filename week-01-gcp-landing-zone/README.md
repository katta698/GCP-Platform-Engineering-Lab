# Week 01 — Landing Zone

**Status:** ✅ Deployed — 15 resources, 0 changed, 0 destroyed.

The resource hierarchy every later week sits inside: folders that policy can
attach to, and the platform projects that outlive any single week.

Write-up: [A GCP Landing Zone, and Why It Is Not Two Accounts](https://jayanthkatta.com/blog/week-01-gcp-landing-zone/)

## Cost note

**Zero.** Not "a few cents" — organizations, folders, projects, IAM bindings and
API enablement are all free. Nothing here bills per hour.

This week is **permanent infrastructure**. Every later week creates its projects
inside these folders, so tearing it down orphans the lab. `scripts/cleanup.sh`
refuses to run without `--i-really-mean-it`.

## What is deployed

```
organization
├── platform                    folder
│   ├── net-hub                 compute, dns, networkmanagement
│   ├── logging                 logging, monitoring, bigquery
│   └── security                cloudkms, secretmanager
└── workloads                   folder
    ├── dev                     folder — later weeks create dev projects here
    └── prod                    folder
```

| Resource | Why |
| --- | --- |
| `platform` folder | Shared services that outlive any one week |
| `workloads/{dev,prod}` folders | Environment separation the org policy service can attach to. A label could not do this |
| Three platform projects | Split by blast radius — whoever can rotate a KMS key should not also be able to rewrite the network |
| `project-factory` module | Every later week creates its projects the same way: same labels, explicit API list, no default network |

## Design notes

**Why folders and not projects.** A governance/workload split maps onto folders
in Google Cloud, not onto projects. A project is free, created in seconds, and is
the unit that owns IAM, quota, API enablement and billing attribution — so
rationing projects concentrates exactly what the split was meant to separate. The
full argument is in the [repository README](../README.md).

**`auto_create_network = false` on every project.** The default network arrives
with permissive firewall rules nobody chose. Every network in this lab is
created explicitly.

**`activate_apis` defaults to empty.** A project that enables nothing has the
smallest possible surface; each week adds only what it uses.

**Timings, measured on the apply.** Folders created in 11–12 seconds. Projects
took 3m15s, 3m50s and 5m33s. Project creation is genuinely slow — worth knowing
before assuming an apply has hung.

## Layout

```
week-01-gcp-landing-zone/
├── terraform/
│   ├── main.tf                        folders + platform projects
│   ├── versions.tf                    HCP workspace gcp-week-01
│   └── modules/project-factory/       reusable project creation
├── scripts/{deploy.sh,validate.sh,cleanup.sh}
└── docs/
    ├── architecture/                  standalone SVG diagram
    └── blog/screenshots/              committed evidence
```

There is no `environments/dev` and `environments/prod` split here, unlike later
weeks. The hierarchy is org-wide: there is one set of folders, and dev and prod
are objects *inside* it rather than two deployments of it. The workspace is
`gcp-week-01`, with no `-dev` suffix, for the same reason.

## Running it

Terraform reads Application Default Credentials, not your `gcloud auth login`
session:

```bash
gcloud auth application-default login
```

Then:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Fill in the organization ID, billing account and three globally unique project
IDs. `terraform.tfvars` is gitignored and must stay that way.

```bash
cd terraform && terraform init && terraform plan
```

Expect 15 resources: 4 folders, 3 projects, 8 API enablements.

## Verifying it

State can be confidently wrong, so check Google Cloud directly rather than
trusting it:

```bash
./scripts/validate.sh
```

```bash
terraform plan -detailed-exitcode   # 0 = no drift
```

The field that matters on a project is `parent.id` — it is the difference
between a project that is *in* the hierarchy and one that merely exists.

## Prerequisites

An **organization**, which requires Cloud Identity on a domain you control.
Folders and organization policy do not exist without one, and there is no API
that creates an organization — it appears when a user from a verified domain
first signs in to the Cloud console.

The identity running this needs `resourcemanager.organizationAdmin`,
`folderCreator` and `projectCreator` at the organization, plus `billing.user` on
the billing account. Organization Administrator does **not** include
`folders.create`; that grant is separate and easy to miss.

# Week 01 — GCP Landing Zone

**Status:** 🔨 Scaffolded, not deployed — blocked on [`../docs/SETUP.md`](../docs/SETUP.md).

Builds the resource hierarchy everything else in this lab sits inside: folders
for environment separation, projects created from a reusable module, a service
account for CI, and enough IAM to make the hierarchy meaningful rather than
decorative.

## Cost note

Resource Manager objects — organizations, folders, projects, IAM bindings — are
free. This week creates no compute, no storage beyond the bootstrap state
bucket, and nothing that bills per hour. It is intended to **stay deployed
permanently**; every later week depends on it. `scripts/cleanup.sh` therefore
refuses to run without an explicit confirmation flag.

## What gets built

| Resource | Why |
| --- | --- |
| `folders/platform` | Shared services that outlive any one week |
| `folders/workloads/{dev,prod}` | Environment separation enforced by hierarchy, not naming convention |
| Project factory module | Every later week creates its project the same way, with the same labels and API enablement |
| CI service account + WIF pool | Keyless authentication from GitHub Actions — no service account keys anywhere in this lab |
| Baseline IAM at folder scope | Grants inherit down, so per-project bindings stay rare and reviewable |

## Prerequisite that decides the shape of this week

Folders require an organization. If Option A was chosen in `docs/SETUP.md`
(no Cloud Identity organization), the folder hierarchy cannot be created and
this week reduces to project creation plus IAM. Confirm which option is live
before writing the Terraform — the decision is recorded in
`../SESSION_CONTEXT.md`.

## Layout

```
week-01-gcp-landing-zone/
├── terraform/
│   ├── modules/project-factory/   # reusable project creation
│   └── environments/{dev,prod}/
├── scripts/{deploy.sh,validate.sh,cleanup.sh}
└── docs/
    ├── architecture/              # SVG diagram for the blog post
    ├── blog/screenshots/          # committed evidence
    ├── references.md
    └── interview-questions.md
```

## Blog posts this feeds

GCP Architecture Series phase 1 (Foundations and governance), roughly #1–#8 —
resource hierarchy, projects, folders, billing association, and the case for
Terraform-managed hierarchy. See `GCP-ROADMAP.md` in the blog repo for the
authoritative numbering; do not renumber published posts.

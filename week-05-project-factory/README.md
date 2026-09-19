# Week 05 — Project factory

Status: ✅ **Deployed 2026-09-19.** Constraint in dry run.

## Cost note

**$0.** A project, a tag key with two values, an essential contact and a custom
constraint. None of it bills. The project holds nothing that runs — no compute,
no storage, no network of its own.

Worth naming the non-monetary cost instead: **a project ID is permanent and is
never released for reuse.** `katta698-gcp-dev-app-01` was spent in Week 04 and
is gone forever, even though the project was deleted. That is the resource this
week actually consumes.

## What this week builds

```
organization
├── tagKeys/environment              values: dev, prod   (IAM-controlled, closed)
└── custom.requireProjectNamingAndParent           DRY RUN
    projectId must start with the org prefix, parent must be a folder

workloads/dev
└── katta698-gcp-dev-app-02          built by modules/project
    labels  week=05, env=dev, managed-by=terraform
    tag     environment=dev
    essential contact · no default network · deletion_policy PREVENT
```

Four projects existed before this week and they agree on the important things —
all five carry `week`, `env` and `managed-by`. But nothing *required* it. They
agree because three were written in one sitting and the fourth copied them. The
factory is what turns a habit into a property.

## The module refuses to make the important things optional

No `auto_create_network` toggle. Labels always set. Essential contact always
set. `deletion_policy` stated rather than inherited. A factory whose every
control has a switch produces whatever the caller asked for, which is what it
was meant to replace.

The one thing it does make optional is the deletion lien, because most projects
should be deletable — a lab that cannot tear down its own work accumulates cost
and confusion.

## Measured findings

**A custom constraint on a project cannot read that project's labels.** This is
the week's result, and it invalidated the original design. The constraint was
rejected with:

```
Error 400: Request has invalid values
```

which names nothing. Probing field by field settled it:

| field on `cloudresourcemanager.googleapis.com/Project` | |
| --- | --- |
| `resource.projectId` | **accepted** |
| `resource.parent` | **accepted** |
| `resource.labels` | **rejected** |
| `resource.displayName` | **rejected** |

The reference lists `Project` as supported — at **Preview** — and never publishes
which of its fields are exposed. "Require labels on project creation" is simply
not achievable, and no amount of reading would have revealed that.

What is enforceable is arguably better. A project ID is permanent and globally
unique, so a name that breaks the standard can never be corrected, only
abandoned. And a project created at the organization root inherits none of the
folder-level policy this lab spent three weeks building.

**Creating a tag and binding a tag are different roles.**
`roles/resourcemanager.tagAdmin` creates tag keys and values and carries **no**
`tagValueBindings.create`; that is in `roles/resourcemanager.tagUser`. The
failure was a bare `Error 403: The caller does not have permission`, naming
neither the permission nor a role. Same shape as Week 04's firewall policy
split, where creating a policy and attaching it needed different roles.

**Creating a project confers no right to administer its contacts.** `tf-apply`
created the project and was then refused on its essential contact, needing
`roles/essentialcontacts.admin` separately.

**The `user_project_override` cascade continues.** Week 04 had to enable three
APIs on its quota project; this week added a fourth, `essentialcontacts`, for
the same reason — every call is attributed to the quota project, so it needs
APIs it does not itself use.

**An enforced constraint can make a resource un-reconcilable with its own
config.** Freeing the project slot meant destroying Week 04's spoke, and the
apply failed first: Terraform wanted to remove `block-project-ssh-keys` metadata
added during Week 04's testing, and the now-enforced
`compute.managed.blockProjectSshKeys` refused the removal. The config said one
thing, the live resource another, and policy blocked closing the gap.

**The real limit on a project factory is a billing quota.** The account caps
linked projects at five. This week could only run because Week 04's service
project was deleted to free a slot — the hub VPC, its subnets and the firewall
policy were kept, since they occupy no slot and Weeks 13–19 build on them.
Raising the cap is a Console form Google may attach a payment to. No amount of
Terraform addresses it.

## Order of work

1. Read live state — with `--effective`, and check the billing slot count first
2. Grant what CI cannot yet do, in **`week-02-keyless-ci`**, hand-applied
3. `terraform apply` here — remote, as `tf-apply`
4. `ORG_ID=... PROJECT_ID=... ./scripts/validate.sh`
5. Promote the constraint only after reading a dry-run violation

Step 2 happened four times this week: `tagAdmin`, `tagUser`,
`essentialcontacts.admin`, and the viewer counterparts. Each failure named a
permission or nothing at all, never a role.

## Evidence

- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/references.md` — what each source settled, and what none of them did

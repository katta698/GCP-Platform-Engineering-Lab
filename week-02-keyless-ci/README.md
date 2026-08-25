# Week 02 — Keyless CI

**Status:** 🔨 In progress.

The baseline this organization inherited, what it already decided, and the only
path it leaves open.

## Cost note

**Zero.** Workload identity pools, providers, service accounts and IAM bindings
are all free, and nothing here bills per hour or per token exchange.

This week is **permanent infrastructure** and is **exempt from teardown**. It is
the authentication path for every later week — destroying it breaks every remote
workspace at once and leaves no credential anywhere that can rebuild it.
`scripts/cleanup.sh` refuses to run without `--i-really-mean-it`.

## The premise, checked before writing anything

Google Cloud enforces a **security baseline** on every organization created on or
after 3 May 2024. It is applied at creation, by Google, without being asked for.
This organization was created 21 August 2026, so it arrived with all seven:

```
iam.managed.disableServiceAccountKeyCreation
iam.disableServiceAccountKeyUpload
iam.automaticIamGrantsForDefaultServiceAccounts
iam.allowedPolicyMemberDomains
essentialcontacts.managed.allowedContactDomains
compute.managed.restrictProtocolForwardingCreationForTypes
storage.uniformBucketLevelAccess
```

That is read from the organization, not from documentation.

The first two are the week. The usual Google Cloud CI failure — a service account
key in a file, or pasted into a CI variable — was impossible here before anyone
decided it should be. So this week is not "ban the shortcut, then build the
alternative". The shortcut was already banned. The week is: find out what the
platform decided on your behalf, prove it by trying to create a key and watching
it fail, and then build what is left.

## What is deployed

```
seed project
├── hcp-terraform                 workload identity pool
│   └── hcp-terraform-oidc        provider — issuer https://app.terraform.io
├── tf-plan     service account   read-only, assumed during the plan phase
└── tf-apply    service account   assumed during the apply phase
```

| Resource | Why |
| --- | --- |
| Pool + OIDC provider | Exchanges an HCP-minted token for a federated Google credential. Nothing is stored |
| `attribute_condition` | Narrows a **public** issuer to one HCP organization, one project, one workspace prefix |
| Two service accounts | The plan phase and the apply phase assume different identities |
| Org-level role bindings | Granted at the organization because folders and projects are created as its children |
| Billing account binding | The billing account is outside the hierarchy; an org grant does not reach it |

## Design notes

**Why the pool lives in the seed project.** CI identity is a bootstrap concern:
the project that created the hierarchy also holds the identity that maintains it.
The obvious alternative, the security project, would hand a project scoped to
keys and secrets an org-level administrative reach it has no other reason to
hold.

**The attribute condition is the whole security boundary.** `app.terraform.io`
is a public issuer. Every HCP Terraform user on earth holds a validly signed
token from it, and the provider's resource name is not a secret — it is printed
in plan output. Without a condition, the only thing between a stranger and this
organization is that they have not read it. The condition checks three claims:
the HCP organization, the project inside it, and the workspace name prefix. The
AWS lab's workspaces sit in the same HCP organization and carry tokens from the
same issuer; the project and prefix checks are what keep them out.

**Splitting plan from apply is enforced by Google, not by convention.** HCP names
the two identities separately (`TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` and
`TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL`) and the token carries a
`terraform_run_phase` claim. Each service account's impersonation binding is
scoped to one phase, so a plan-phase token cannot assume the apply identity —
the binding does not match. A speculative plan on a pull request therefore holds
no role that can change anything.

**Where this may fail, and why that is interesting.** The same baseline that bans
keys also enforces `iam.allowedPolicyMemberDomains` — domain-restricted sharing —
set here to a single Cloud Identity customer ID. That constraint governs members
in IAM allow policies, and federated principals appear in those policies as
`principalSet://` members rather than as a domain. Whether it blocks the binding
that makes the keyless path work is settled by running the apply, not by reading
about it. The outcome is recorded here once measured.

## Layout

```
week-02-keyless-ci/
├── terraform/          pool, provider, service accounts, bindings
├── scripts/            deploy, validate, cleanup (guarded)
└── docs/               references, screenshots
```

## Order of work

1. Read the enforced baseline off the organization. Attempt a key, capture the denial.
2. Apply this week from human credentials — the last hand-run apply in the lab.
3. Set the workspace variables in HCP, flip `gcp-week-02` to remote execution, re-run.
4. Retrofit `gcp-bootstrap` and `gcp-week-01` to remote execution and connect the repo.
5. Validate against the organization, capture screenshots, write up.

## Verify

```bash
ORG_ID=... SEED_PROJECT=... ./scripts/validate.sh
```

The last check attempts to create a service account key and **fails the script if
it succeeds**. A week that claims keys are impossible should test that claim
every time it runs, not once on the day it was written.

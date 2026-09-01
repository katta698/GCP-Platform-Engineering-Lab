# Week 02 — Keyless CI

**Status:** ✅ Deployed 2026-08-25 — 18 resources, workspace `gcp-week-02`.

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
about it.

**Measured 2026-08-25: it does not block them.** Both federation bindings were
created without complaint, with the constraint enforced and scoped to one Cloud
Identity customer ID throughout. The reasoning that fits the result: the
constraint tests *principals identified by a domain*, and a principalSet is
identified by pool and attribute, so there is no domain for it to test. The
documentation does not state this either way — the page describes the constraint
in terms of users, groups and service accounts, and a federated principal is none
of those.

## Measured findings

Everything in this section came from the deployment, not from documentation.

**The attribute condition's string comparison is case-sensitive, and the claim
carries a name no human-facing surface shows.** The HCP organization's stored
name is lowercase. Every surface that resolves it — the console URL, the
`cloud {}` block in `versions.tf`, the workspace list — is case-insensitive and
displays it capitalised. The token carries the true value, so a condition written
against the displayed spelling rejects every token. The error names no claim:
only *"The given credential is rejected by the attribute condition."* Both ends
look correct and nothing works. Cost roughly forty minutes, and it is the reason
`hcp_organization` in `variables.tf` carries a comment longer than the variable.

**`roles/viewer` at the organization cannot read a folder.** Basic roles predate
the resource hierarchy: they describe a project's contents, not the structure a
project hangs from. `resourcemanager.folders.get` is not among their thousands of
permissions, and downward inheritance does not add it. A remote plan of Week 01
failed on exactly that. `roles/browser` is what grants it. Removing
`roles/viewer` was a separate and larger win — it confers
`storage.legacyObjectReader` on every bucket in every project, including projects
that do not exist yet.

**`terraform init` creates new workspaces in HCP's `Default Project`,** not in
the project the sibling workspaces live in. That is what initially put
`gcp-week-02` outside `GCP Platform Lab`, and it explains an execution mode that
appeared to ignore the UI: the workspace inherited Default Project's default of
`remote` with `setting-overwrites.execution-mode = false`, so setting the radio
button did not stick until that inheritance was broken. The attribute condition
is what surfaced it — the `terraform_project_name` claim did not match, so a
security control caught a governance mistake. That is the argument for writing
the condition tightly rather than leaving the project check out.

**`gcloud auth login` and Application Default Credentials are separate credential
stores,** and Cloud Identity's reauthentication policy expires ADC independently
of the CLI login. The symptom is `invalid_grant / invalid_rapt`, whose error text
links a Workspace administration article about session control and never mentions
`gcloud auth application-default login`. That command also **clears the ADC quota
project**, so `gcloud auth application-default set-quota-project` has to follow
it.

**The federation is proven end to end.** `gcp-week-01` planned on an HCP agent
with no Google Cloud credential stored anywhere, refreshed 4 folders and 3
projects, and returned `No changes`.

## Execution modes, and why two workspaces stay local

| Workspace | Mode | Why |
| --- | --- | --- |
| `gcp-bootstrap` | local | Human layer — seed project and billing budget |
| `gcp-week-02` | local, **permanently by design** | Defines who CI is |
| `gcp-week-01` | remote | Retrofitted 2026-08-25; the proof federation works |
| Weeks 03+ | remote | Run as `tf-apply` |

For `tf-apply` to apply *this week's* configuration it would need
`resourcemanager.organizations.setIamPolicy` — which exists only in Organization
Administrator, and would let it grant itself anything — and admin on the pool,
which would let it rewrite the attribute condition and trust whoever it liked.
**An identity must not manage its own grants.** The same reasoning removed the
billing binding from the configuration.

A consequence worth stating so nobody tries to fix it: local execution disables
remote execution, and version control integration is only available to workspaces
with remote execution. So `gcp-bootstrap` and `gcp-week-02` will show an empty
Repository column in HCP **forever**, and that is correct.

## Layout

```
week-02-keyless-ci/
├── terraform/          pool, provider, service accounts, bindings
├── scripts/            deploy, validate, cleanup (guarded)
└── docs/
    ├── references.md           sources, and what each one settled
    ├── interview-questions.md  PCA material drawn from this deployment
    └── blog/screenshots/       evidence
```

## Order of work

1. Read the enforced baseline off the organization. Attempt a key, capture the denial.
2. Apply this week from human credentials — the last hand-run apply in the lab.
3. Set the workspace variables in HCP, then re-run.
4. Retrofit `gcp-week-01` to remote execution and connect the repo. `gcp-bootstrap`
   and this week's own workspace stay local — see the table above.
5. Validate against the organization, capture screenshots, write up.

Step 3 originally read "flip `gcp-week-02` to remote execution". That was the
plan going in and it was wrong; the reasoning that replaced it is in *Execution
modes* above. The step is left corrected rather than deleted because the
correction is the interesting part.

## Verify

```bash
ORG_ID=... SEED_PROJECT=... ./scripts/validate.sh
```

The last check attempts to create a service account key and **fails the script if
it succeeds**. A week that claims keys are impossible should test that claim
every time it runs, not once on the day it was written.

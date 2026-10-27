# Lab Guide — Week 01: Resource Hierarchy and Landing Zone

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-01-gcp-landing-zone/)
explains what it does and why; this guide is the runbook.

**Status:** deployed 2026-08-21. **Permanent** — every later week sits inside the
hierarchy this one creates, so there is no teardown.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| A domain you own and administer | required for Cloud Identity, and therefore for the organization. A `@gmail.com` account structurally cannot have one |
| Cloud Identity Free | not Workspace; Workspace is paid and adds nothing here |
| Billing account | with a free project slot, and see §3 if it belongs to a different identity |
| Operator | `roles/resourcemanager.organizationAdmin` **and** `roles/resourcemanager.folderCreator` — see §3 |
| HCP Terraform | an organization and a workspace, `gcp-bootstrap` |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

### Nothing creates an organization

There is no `gcloud organizations create`. The subcommands are `list`,
`describe` and three IAM verbs — no create, no delete — and there is no Resource
Manager API for it either.

An organization is not provisioned. It **appears** when a domain is verified in
Cloud Identity *and* an account from that domain signs in to the Cloud console
and accepts the terms. The first step of an infrastructure-as-code landing zone
is therefore a web form, and there is no way around it.

**Cloud Identity Free has no mailbox.** If the domain has no MX records the
super-admin address cannot receive mail, so there is no password-reset path. Set
a recovery address you actually read during sign-up, and enrol a second factor
immediately.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive** |
| `billing_account` | funds the platform projects — **sensitive** |
| `project_prefix` | prepended to every generated project ID |

---

## 3. Grant yourself access to your own organization

When an organization is created Google grants the **whole domain** exactly two
roles: `roles/billing.creator` and `roles/resourcemanager.projectCreator`.
Neither lets you see or administer the organization.

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:<you>@<your-domain>" \
  --role="roles/resourcemanager.organizationAdmin"

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:<you>@<your-domain>" \
  --role="roles/resourcemanager.folderCreator"
```

**`folderCreator` is not optional.** Organization Administrator lets you
*manage* folders but does not include `resourcemanager.folders.create`. Week 01
fails without it.

**Being Cloud Identity super admin does not make you an organization admin.**
Two separate systems. Google's own documentation says the super administrator who
creates the organization is assigned Organization Administrator automatically;
measured 2026-08-21, **that did not happen on this account**. The two
domain-wide roles the documentation describes were present exactly as described;
Organization Administrator was not.

### Cross the billing boundary

If the billing account belongs to a different identity — a personal account that
predates the organization — no organization-level role reaches it. Signed in as
the **owning** identity:

```bash
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
  --member="user:<you>@<your-domain>" \
  --role="roles/billing.user"
```

Without this, `google_project` creation fails on the billing association, and
the error does not point at a cross-identity permission problem.

---

## 4. Deploy

```bash
cd week-01-gcp-landing-zone/terraform
terraform init
terraform plan      # expect: 15 to add on a clean organization
terraform apply
```

**Expected output:** `Apply complete! Resources: 15 added, 0 changed, 0 destroyed.`

| Resource group | Purpose |
| --- | --- |
| `google_folder` ×4 | `platform`, `workloads`, and `dev` / `prod` beneath `workloads` |
| `module "network_hub"` | the project that will hold the Shared VPC |
| `module "logging"` | the project that will hold the log sinks |
| `module "security"` | the project that will hold key management |
| `google_project_service` (per project) | APIs are opt-in, one resource each, `disable_on_destroy = false` |

**Expect the apply to take minutes.** Measured 2026-08-21: folders created in
**11–12 seconds**; projects took **3m15s, 3m50s and 5m33s**. Nothing is wrong —
that is how long project creation takes. Worth knowing before concluding an apply
has hung.

### Why folders rather than labels

`dev` and `prod` are **folders** because the point of the split is that policy
attaches to it. An organization policy on `workloads/prod` constrains every
project beneath it, including projects that do not exist yet. A label constrains
nothing.

### Why three platform projects rather than one

Split by blast radius, not by convenience. Whoever can rotate a key should not
thereby be able to rewrite the network, and whoever can read every log line in
the estate should not be able to do either. A project is the unit that owns IAM,
quota and API enablement, so three projects is three IAM surfaces — and costs
exactly the same as one.

### The project factory

```hcl
resource "google_project" "this" {
  name            = var.display_name
  project_id      = var.project_id
  folder_id       = var.folder_id
  billing_account = var.billing_account

  auto_create_network = false

  labels = local.labels
}
```

`auto_create_network = false` everywhere, so the default network's permissive
firewall rules never exist to be forgotten about. `activate_apis` defaults to an
**empty list**: a project that enables nothing has the smallest possible
surface, and each week adds only what it uses.

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-08-21 |
| --- | --- | --- |
| Terraform agrees with itself | `plan -detailed-exitcode` returns 0 | 0, no drift |
| The folder tree exists | 4 folders in the right nesting | 4, correct |
| Each project's **parent** | the folder, not nothing | correct for all three |
| No default network | `auto_create_network = false` honoured | no network in any project |
| API enablement | only what each project uses | 2–3 per project |
| The console shows the hierarchy | organization, folders, projects | shown |

**`parent.id` is the field that matters.** It is the difference between a project
that is *in* the hierarchy and one that merely exists:

```bash
gcloud projects describe <PROJECT_ID> \
  --format="value(projectId,lifecycleState,parent.id)"
```

**Query Google Cloud, not Terraform state.** State can be confidently wrong.

---

## 6. Troubleshooting

### `gcloud organizations list` returns `Listed 0 items` for an organization that exists

**Cause.** `gcloud` queries the **v3** Resource Manager API, which returns only
organizations you hold `resourcemanager.organizations.get` on. A raw **v1**
`organizations:search` call with the same credentials returns it immediately.

**Fix.** Grant yourself `organizationAdmin` (§3). **Zero items is not evidence of
absence — it is evidence of a missing permission**, and the two are
indistinguishable from the CLI.

### Verifying the domain did not create the organization

**Cause.** It appears only when an account from the domain first signs in to the
Cloud console and accepts the terms, not at verification.

**Fix.** Sign in. Combined with the previous entry this produces a stretch where
you cannot tell whether the organization does not exist yet or exists and is
invisible.

### Terraform ignores the credentials you just created

**Cause.** `gcloud auth login` authenticates the CLI; the Terraform provider
reads **Application Default Credentials**, a separate store.

**Fix.** `gcloud auth application-default login`. Note that the ADC consent
screen's checkboxes are **not ticked by default** — clicking through produces a
confident success followed by *"cloud-platform scope is required but not
consented"*. The page looks complete when nothing is selected.

### A state bucket the configuration has to create before it can use it

**Cause.** A GCS backend needs a bucket that the same configuration creates.

**Fix.** Either the standard dance — apply with local state, add the backend
block, `terraform init -migrate-state` — or an external backend. **HCP Terraform
needs nothing to pre-exist inside Google Cloud**, which is a real argument for
an external backend at the bootstrap layer independent of any consistency
argument.

---

## 7. Known limitations

- **No organization policy yet.** `dev` and `prod` were created precisely so they
  could carry different constraints, and this week adds none. An empty `prod`
  folder that enforces nothing is a false sense of separation; constraints arrive
  in Week 03.
- **Local execution, so no run history.** A plan read on a laptop is the only
  record. Remote execution arrives in Week 02, once federation exists.
- **Every binding names a user.** Group-based access arrives in Week 10.
- **The super admin is also the organization admin.** One identity holding both
  Cloud Identity super-admin and `organizationAdmin` is one account away from
  total compromise. Flagged here rather than quietly left; **not yet split** in
  this series.
- **No teardown.** `scripts/cleanup.sh` refuses to run without
  `--i-really-mean-it`, because tearing this down orphans the whole lab.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Super admin | Break-glass only, never a daily driver. Organization Administrator belongs on a separate identity |
| Execution | Remote runs and federated credentials before the first apply, not in a later week |
| Policy | Organization policy in the same change as the folders, so a `prod` folder means something the day it exists |
| Budgets | Guardrail first. Nothing here costs money, which is exactly what makes it easy to defer |
| Access | Bind to groups, not users, so access survives people joining and leaving |

---

## 9. References

- [Resource hierarchy](https://docs.cloud.google.com/resource-manager/docs/cloud-platform-resource-hierarchy)
- [Creating and managing organizations](https://docs.cloud.google.com/resource-manager/docs/creating-managing-organization)
- [Creating and managing folders](https://docs.cloud.google.com/resource-manager/docs/creating-managing-folders)
- [IAM policy inheritance](https://docs.cloud.google.com/iam/docs/resource-hierarchy-access-control)
- [Set up Cloud Identity](https://docs.cloud.google.com/identity/docs/set-up-cloud-identity-admin)

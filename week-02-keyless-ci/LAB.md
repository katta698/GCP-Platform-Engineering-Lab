# Lab Guide — Week 02: Keyless CI with Workload Identity Federation

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-02-keyless-ci/)
explains what it does and why; this guide is the runbook.

**Status:** deployed 2026-08-25. Still running — every later week depends on it.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with a seed project for bootstrap concerns |
| HCP Terraform | an organization and a workspace; note the **real** org name is lowercase (see §6) |
| Operator | `roles/resourcemanager.organizationAdmin` — this week **cannot** be run by CI, by design |
| APIs | `iam.googleapis.com`, `sts.googleapis.com`, `cloudresourcemanager.googleapis.com` |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

### This week is deliberately human-run

**An identity must not manage its own grants.** For `tf-apply` to apply this
configuration it would need:

- `resourcemanager.organizations.setIamPolicy` — only in `organizationAdmin`,
  which would let it grant itself anything
- admin on the workload identity pool — it could rewrite the attribute condition
  and trust whoever it liked

So `gcp-week-02` runs **local execution, permanently and on purpose**. The lab
has two layers: `gcp-bootstrap` and `gcp-week-02` are human-run and define who CI
*is*; Week 01 and Weeks 03+ run remotely *as* CI.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive** |
| `seed_project_id` | hosts the pool, provider and service accounts |
| `hcp_organization` | HCP Terraform organization name — **case matters**, see §6 |

---

## 3. Deploy

```bash
cd week-02-keyless-ci/terraform
terraform init
terraform plan      # expect: 18 to add on a clean organization
terraform apply
```

**Expected output:** `Apply complete! Resources: 18 added, 0 changed, 0 destroyed.`

| Resource | Purpose |
| --- | --- |
| `google_iam_workload_identity_pool` | `hcp-terraform` — the trust boundary |
| `google_iam_workload_identity_pool_provider` | issuer `https://app.terraform.io`, with the attribute condition |
| `google_service_account` ×2 | `tf-plan` (read) and `tf-apply` (write) |
| `google_organization_iam_member` ×N | the roles each identity holds |
| `google_service_account_iam_member` ×2 | which principalSet may impersonate which account |

**The file has grown since.** It now carries every grant later weeks needed —
Week 04's compute roles, Week 07's asset roles, Week 08's deny roles — because
this is the human-run layer where CI's permissions are defined. Expect it to keep
growing; that is the design, not drift.

---

## 4. The two things that make this secure

### The attribute condition is the whole boundary

`app.terraform.io` issues tokens for **every** HCP organization, not just yours.
Without a condition pinning the organization, any HCP user anywhere could
exchange a token for your service account.

```
assertion.terraform_organization_name == "katta"
```

**Lowercase.** Every human-facing surface shows `Katta` — the console URL, the
`cloud {}` block, the workspace list — and HCP resolves those
case-insensitively. The OIDC token carries the true value and Google's CEL
comparison is case-sensitive, so `== "Katta"` rejects every token. The error
names no claim:

```
The given credential is rejected by the attribute condition.
```

Both ends look correct and nothing works. Cost roughly forty minutes.

### The plan/apply split is enforced by Google, not by convention

HCP names the two identities separately
(`TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL`)
and the token carries a `terraform_run_phase` claim. Each service account's
`workloadIdentityUser` binding is a principalSet scoped to one phase:

```
principalSet://iam.googleapis.com/<pool>/attribute.terraform_run_phase/plan
principalSet://iam.googleapis.com/<pool>/attribute.terraform_run_phase/apply
```

A plan-phase token **cannot** assume the write identity — the binding does not
match. Enforced at token exchange. A speculative plan on a pull request holds no
role that can change anything.

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual |
| --- | --- | --- |
| Security baseline constraints enforced | present | 7 constraints, from organization creation |
| Workload identity pool | exists, correct issuer | present |
| Provider and its attribute condition | pins the HCP organization | present, lowercase |
| Service accounts | `tf-plan` and `tf-apply` | both |
| Who may impersonate the apply account | the apply-phase principalSet only | correct |
| Plan identity cannot write | no write roles | confirmed |
| **The shortcut, attempted** | key creation refused | `FAILED_PRECONDITION`, see below |

### The denial, attempted 2026-10-25

```bash
gcloud iam service-accounts keys create /tmp/x.json \
  --iam-account=tf-plan@<SEED>.iam.gserviceaccount.com
```

```
FAILED_PRECONDITION: Operation denied by org policy
["constraints/iam.managed.disableServiceAccountKeyCreation":
 "This constraint, when enforced, blocks service account key creation."]
reason: CUSTOM_ORG_POLICY_VIOLATION
```

No key was created — confirmed with `keys list --managed-by=user`, which returns
nothing.

**`FAILED_PRECONDITION`, not `PERMISSION_DENIED`.** That distinction is the
point: an under-privileged attempt fails with a permission error indistinguishable
from the control working. This request passed the IAM check and was refused by the
policy, which the response names explicitly.

**It is the MANAGED generation doing the work.** The legacy constraint of the
same name has no policy and reads `enforce: false` — which nearly produced a
false security alarm in Week 09. Check both generations before concluding
anything.

---

## 6. Troubleshooting

### `The given credential is rejected by the attribute condition`

**Cause.** The HCP organization name's real value is lowercase; every UI shows it
capitalised, and Google's CEL comparison is case-sensitive.

**Fix.** `== "katta"`. The error names no claim and both ends look correct.

### A workspace appears in HCP's Default Project with an execution mode that ignores the UI

**Cause.** `terraform init` creates a missing workspace in **Default Project**,
not the project your other workspaces live in. It then inherits that project's
default of `remote` with `setting-overwrites.execution-mode = false`, so setting
the radio button does not stick until the inheritance is broken.

**Fix.** Create the workspace through the API with an explicit `project`
relationship — `scripts/hcp_workspace.py` in this repo does it.

**Note:** the attribute condition *caught* this misplacement, which is a security
control surfacing a governance mistake, and the argument for writing it tightly.

### `roles/viewer` at the organization cannot read a folder

**Cause.** Basic roles predate the resource hierarchy — they describe a
project's contents, not the structure a project hangs from. Downward inheritance
does not help.

**Fix.** `roles/browser` grants `resourcemanager.folders.get`.

### `invalid_grant / invalid_rapt` from gcloud

**Cause.** `gcloud auth login` and Application Default Credentials are separate
credential stores, and Cloud Identity's reauth policy expires ADC independently.

**Fix.** `gcloud auth application-default login` — which also **clears the ADC
quota project**, so `application-default set-quota-project` has to follow it. The
error text links a Workspace admin article about session control and never
mentions the command that fixes it.

---

## 7. Known limitations

- **`gcp-week-02` cannot be run by CI**, by design. It is the human-run layer.
- **The pool trusts one HCP organization, not one workspace.** Any workspace in
  that organization can obtain a token. Narrowing to a workspace would mean an
  additional attribute condition.
- **`main.tf` accumulates every grant later weeks need**, so reading it tells you
  what CI can do today but not why each role was added — that history is in each
  week's own notes.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Scope | Condition on workspace as well as organization, so one compromised workspace cannot assume the apply identity |
| Review | Re-review the apply identity's roles on a schedule; this file only grows |
| Separation | A separate pool per environment, so a non-production workspace cannot reach production identities |
| Break-glass | A documented path for when federation itself is broken, which currently does not exist |

---

## 9. References

- [Workload Identity Federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation)
- [HCP Terraform dynamic credentials for GCP](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/gcp-configuration)
- [Attribute conditions](https://docs.cloud.google.com/iam/docs/workload-identity-federation#conditions)
- [Organization policy: disable service account key creation](https://docs.cloud.google.com/resource-manager/docs/organization-policy/restricting-service-accounts)

# Lab Guide — Week 10: Group-Based Access Control

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-10-group-access/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-10-24, then torn down. Every output
below is real. Where something was not verified, it says so.

---

## 1. Prerequisites

### Accounts and identity

| Requirement | Detail |
| --- | --- |
| Cloud Identity | Free edition is sufficient, on a verified domain |
| Super Admin | Needed once, for the Admin console step in §3 |
| GCP organization | A folder containing at least one project |

### Permissions

The Terraform **apply** identity needs:

| Role | Why |
| --- | --- |
| `roles/resourcemanager.folderAdmin` | carries `folders.setIamPolicy` |
| `roles/iam.serviceAccountAdmin` | creates the test service account |
| **Group Administrator** (Workspace admin role) | create and manage groups — **not** a GCP IAM role, see §3 |

It does **not** need `roles/resourcemanager.organizationAdmin`. The lab is
folder-scoped precisely because the pipeline identity does not hold it.

The Terraform **plan** identity needs read access to the group. See §8 for an
important caveat about what was and was not proven here.

### Tools

| Tool | Version used |
| --- | --- |
| Terraform | 1.17.0 (config requires `>= 1.9`) |
| `hashicorp/google` provider | 6.50.0 (`~> 6.0`) |
| Google Cloud SDK | 581.0.0 or later |

### APIs

```bash
gcloud services enable cloudidentity.googleapis.com --project=<QUOTA_PROJECT>
```

### Cross-week dependencies

| From | What it supplies | Required? |
| --- | --- | --- |
| Week 1 | folder + project hierarchy | the grant needs a folder; a project alone will not do |
| Week 2 | keyless CI via Workload Identity Federation | **No** — local Terraform with user credentials reproduces the lab |

### Region

None. Every resource is global.

---

## 2. Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored) and fill in:

| Variable | How to obtain it | Sensitive |
| --- | --- | --- |
| `seed_project_id` | any project you can bill API calls to | no |
| `customer_id` | `gcloud organizations describe <ORG_ID> --format="value(owner.directoryCustomerId)"` | **yes** |
| `domain` | your Cloud Identity primary domain | no |
| `platform_folder_id` | `gcloud resource-manager folders list --organization=<ORG_ID>` | no |
| `operator_principal` | the human who will run the validation | **yes** |

`customer_id` and `operator_principal` are account identifiers. They stay in
`terraform.tfvars`, which is gitignored, and are marked `sensitive` in
`variables.tf` so they do not appear in plan output.

---

## 3. The one manual step

Group management is a **Workspace** admin role. No GCP IAM role grants it, and
there is no gcloud or Terraform path — the pipeline cannot bootstrap this for
itself.

**Admin console → Account → Admin roles → Groups Admin → Assign service
accounts** → add the apply identity.

> **Wait before testing.** Workspace admin role assignments take minutes to take
> effect. During that window the Cloud Identity API returns `403 Permission
> denied`, which is indistinguishable from a wrong permission. Measured once
> here at about five minutes; treat that as an anecdote, not a range.

---

## 4. Deploy

```bash
cd week-10-group-access/terraform
terraform init
terraform plan      # expect: 6 to add, 0 to change, 0 to destroy
terraform apply
```

**Expected output:**

```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
```

### What gets created

| Resource | File | Purpose |
| --- | --- | --- |
| `google_project_service.cloudidentity` | [main.tf](terraform/main.tf) | enables the API |
| `google_service_account.group_demo` | [main.tf](terraform/main.tf) | test subject, holds **no** roles |
| `google_service_account_iam_member.operator_can_impersonate` | [main.tf](terraform/main.tf) | lets the operator run the test as the subject |
| `google_cloud_identity_group.log_readers` | [main.tf](terraform/main.tf) | the access group |
| `google_cloud_identity_group_membership.demo_sa` | [main.tf](terraform/main.tf) | subject → group, as `MEMBER` |
| `google_folder_iam_member.log_readers_can_read` | [main.tf](terraform/main.tf) | `roles/logging.viewer` → the group, at the folder |

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

Asserts against the live organization rather than Terraform state:

| Check | Expected |
| --- | --- |
| group exists | `grp-gcp-log-readers@<domain>` resolves |
| subject holds nothing directly | zero org-level bindings naming it |
| subject is a `MEMBER` | not `MANAGER` or `OWNER` |
| folder role held by a **group** | `group:` principal on `roles/logging.viewer` |
| subject can read logs now | query succeeds via impersonation |

**Actual result 2026-10-24:** all checks passed.

### The measurement

```bash
ORG_ID=<ORG_ID> ./scripts/measure-membership-lag.sh 3
```

Removes the membership, polls until access is lost, restores it, polls until
access returns. Three trials each direction, ten-second poll, 600-second
ceiling. **Restores membership in a `trap`**, so a crash cannot leave access
removed.

**Actual result 2026-10-24:**

| Direction | Trial 1 | Trial 2 | Trial 3 |
| --- | --- | --- | --- |
| revoke → access gone | 30 s | 20 s | 10 s |
| grant → access back | 30 s | 30 s | 10 s |

**Observed range: 10–30 seconds, both directions.**

Google documents a propagation delay for membership arriving from an external
identity provider as up to several hours. There is no external provider here,
so that figure describes a different configuration and is not comparable.

---

## 6. Cleanup

```bash
terraform destroy
```

**Expected:** `Resources: 0 added, 0 changed, 6 destroyed.`

### Verify removal against the cloud, not state

```bash
# group should 404
gcloud identity groups describe grp-gcp-log-readers@<domain> \
  --billing-project=<QUOTA_PROJECT>

# service account should be gone
gcloud iam service-accounts describe group-access-demo@<project>.iam.gserviceaccount.com

# folder should carry no group binding for the role
gcloud resource-manager folders get-iam-policy <FOLDER_NUM> \
  --flatten="bindings[].members" \
  --filter="bindings.role=roles/logging.viewer AND bindings.members~^group:" \
  --format="value(bindings.members)"
```

### Not removed by Terraform

**The two Workspace admin roles survive a destroy** — Terraform does not manage
the directory. Revoke by hand in *Admin console → Account → Admin roles*:

- **Groups Admin** on the apply identity
- the custom **Groups → Read** role on the plan identity (then delete the role)

Group Administrator can administer every group in the directory. Leaving it
after the group is gone is a standing privilege with nothing to justify it.

### Deliberately preserved

The folder, the logging project, and the Workload Identity Federation setup from
Week 2 — all shared infrastructure used by later labs.

### Billing

$0 during the lab and $0 after. Verified from the billing export, not estimated.

---

## 7. Troubleshooting

### `Error waiting to create Group: got pending status "not found"` / `403 Permission denied for resource groups/...`

**Cause.** `initial_group_config = "WITH_INITIAL_OWNER"` is documented as making
the caller the group's owner, and is offered as the least-privilege alternative
to a directory-wide admin role. It created the group with **zero members and no
owner** — confirmed through both gcloud and the REST API — so no pipeline
identity could read it.

**Fix.** Assign Group Administrator (§3), wait for propagation, re-apply.

**Note.** Terraform may **replace** the unreadable group rather than adopt it.
Harmless here; on a real access group that replacement would revoke everyone's
access to fix a read error.

### The 403 does not clear after granting the role

**Cause.** Propagation, not permission. See the warning in §3.

**Fix.** Wait about five minutes and re-run unchanged.

### `gcloud identity groups search` returns nothing even though the group exists

**Cause.** `--organization=<ORG_ID>` builds a query against a parent no group can
have. Groups are parented to `customers/<id>`. The command exits 0 and prints
nothing, which looks exactly like "no groups exist".

**Fix.** Use `gcloud identity groups describe <address>`, or REST:

```bash
curl -s -G "https://cloudidentity.googleapis.com/v1/groups:search" \
  --data-urlencode "query=parent=='customers/<CUSTOMER_ID>' && 'cloudidentity.googleapis.com/groups.discussion_forum' in labels" \
  --data-urlencode "view=BASIC" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "X-Goog-User-Project: <QUOTA_PROJECT>"
```

### `SERVICE_DISABLED` naming an unfamiliar project number

**Cause.** Cloud Identity is a client-based API: it bills the caller's project,
and a group belongs to no project. The ADC quota project is **not** honoured by
`gcloud identity groups`.

**Fix.** `--billing-project=<project>` on the CLI;
`user_project_override = true` plus `billing_project` on the provider.

---

## 8. Known limitations

**One control is unproven.** The plan identity was given a custom Workspace role
carrying only *Groups → Read*, and the next apply succeeded — but the Group
Administrator grant was still propagating at that moment. This run **cannot**
separate "the read-only role worked" from "the broader grant took effect". Two
changes were in flight at once. Proving it would mean removing the custom role
and watching the refresh fail; that test was not run.

**An accepted over-grant.** Group Administrator can manage every group in the
directory, including ones it did not create. Cloud Identity documents no
narrower path for a service account. This is a real weakening of the lab's
plan/apply privilege split.

**Free-edition constraint.** Dynamic groups — membership from a query rather
than a list — require Cloud Identity Premium. Everything here is static
membership.

---

## 9. For production

| Area | What would change |
| --- | --- |
| Group hygiene | Use Cloud Identity **security groups**, so access-bearing groups are distinguishable from mailing lists at audit time |
| Governance | A naming convention plus a custom organization policy constraint preventing ad-hoc collaboration groups from being granted IAM roles |
| Monitoring | Alert on membership changes to access groups. Admin console audit logs are **separate** from Cloud Audit Logs — a real monitoring gap |
| Membership source | Drive membership from an HR or IdP system rather than Terraform, accepting the longer propagation that brings |
| Privilege | Replace the Group Administrator over-grant with per-group ownership, if a path that actually confers ownership becomes available |

---

## 10. References

- [Best practices for using Google groups](https://docs.cloud.google.com/iam/docs/groups-best-practices)
- [Setting up the Groups API](https://docs.cloud.google.com/identity/docs/how-to/setup)
- [Creating and searching for Google Groups](https://docs.cloud.google.com/identity/docs/how-to/create-google-groups)
- [Dynamic groups overview](https://docs.cloud.google.com/identity/docs/concepts/overview-dynamic-groups)
- [Terraform `google_cloud_identity_group`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_identity_group)

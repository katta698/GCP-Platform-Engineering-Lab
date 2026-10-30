# Lab Guide — Week 11: Just-in-Time Privileged Access

**How to reproduce this lab.** The blog post explains what it does and why;
this guide is the runbook.

**Status:** deployed 2026-10-29. Still running — teardown removes the
entitlement, the subject and one binding.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with a folder hierarchy (Week 01) |
| Pipeline | the federated `tf-apply` identity (Week 02) |
| Week 02 amendment | `tf-apply` needs `roles/privilegedaccessmanager.admin` — see §2 |
| Operator | `roles/privilegedaccessmanager.admin` on the folder, to approve grants |
| APIs | `privilegedaccessmanager.googleapis.com`, enabled by this week |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

### The amendment is a separate, hand-run apply

`tf-apply` runs every week from 03 onward, and it cannot grant itself the role
this week needs. **An identity must not manage its own grants.** So
`roles/privilegedaccessmanager.admin` is added in Week 02's configuration, which
is human-run permanently, and applied before this week will plan cleanly.

```bash
cd week-02-keyless-ci/terraform
terraform apply      # expect: 1 to add, 0 to change, 0 to destroy
```

It already holds `roles/resourcemanager.folderAdmin`, which folder-level
entitlements also require — creating one needs `setIamPolicy` on the parent.
That is also **why this week attaches to a folder rather than the
organization**: organization-level `setIamPolicy` lives only in
`organizationAdmin`, which the pipeline deliberately does not hold.

---

## 2. Enabling the API is not enabling PAM

The apply will get past the API and fail:

```
Error 400: PAM has not been enabled for this resource "folders/NNN".
Complete the PAM setup process for this resource and retry the operation.
```

Ask the API what is missing rather than guessing:

```bash
gcloud pam check-onboarding-status --folder=<FOLDER> --location=global
```

```json
{
  "findings": [{"iamAccessDenied": {"missingPermissions": [
    "resourcemanager.folders.get",
    "resourcemanager.folders.getIamPolicy",
    "resourcemanager.folders.setIamPolicy"
  ]}}],
  "serviceAccount": "service-org-<ORG>@gcp-sa-pam.iam.gserviceaccount.com"
}
```

Two things worth reading twice.

**The service agent is ORG-scoped** even though the entitlement is attached to a
folder — one agent per organization, addressed by organization number.

**The permission it needs is `setIamPolicy`.** PAM adds and removes grant
bindings by rewriting the folder's IAM policy, so turning PAM on for a resource
hands a Google service agent the ability to change who can do what there. That
is the actual trade, and clicking **Enable** in the console never says so.

`roles/privilegedaccessmanager.folderServiceAgent` contains exactly those three
permissions, and this week grants it in Terraform rather than by hand.

**Note:** `check-onboarding-status` itself needs
`privilegedaccessmanager.locations.checkOnboardingStatus`. An operator holding
`organizationAdmin` does **not** have it.

---

## 3. Configuration

| Variable | Meaning |
| --- | --- |
| `seed_project_id` | where the API is enabled and the subject lives |
| `platform_folder_id` | **in `folders/NNNN` form** — see §6 |
| `operator_principal` | the approver, and the identity that impersonates the subject — **sensitive** |
| `org_id` | only to address the PAM service agent — **sensitive** |
| `elevated_role` | default `roles/iam.securityReviewer` |
| `max_request_duration` | default `1800s`, which is the documented **minimum** |

### 30 minutes is the floor

`max_request_duration` accepts **1800s to 604800s**. There is no way to grant
five minutes of elevated access. That sets the floor on how long each expiry
measurement takes, and it is worth knowing before designing a workflow that
assumes short-lived elevation.

---

## 4. Deploy

```bash
cd week-11-jit-access/terraform
terraform init
terraform plan      # expect: 5 to add
terraform apply
```

| Resource | Purpose |
| --- | --- |
| `google_project_service.pam` | the API, `disable_on_destroy = false` |
| `google_service_account.jit_subject` | holds **nothing**; the entitlement is its only route |
| `google_service_account_iam_member.operator_can_impersonate` | so the operator can act as the subject |
| `google_folder_iam_member.pam_service_agent` | the onboarding from §2 |
| `google_privileged_access_manager_entitlement` | the template: who may ask, for what, for how long, approved by whom |

---

## 5. Run the test

```bash
# 1. the premise: subject holds nothing, folder policy empty, access refused
ORG_ID=... PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... ./scripts/validate.sh

# 2. request, AS THE SUBJECT
PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... ./scripts/request-grant.sh

# 3. approve in the console, as a DIFFERENT principal

# 4. confirm access appeared
GRANT_ACTIVE=1 ... ./scripts/validate.sh

# 5. measure the expiry
PLATFORM_FOLDER_ID=... SEED_PROJECT_ID=... python scripts/measure-expiry-lag.py
```

| Check | Expected | Actual 2026-10-29 |
| --- | --- | --- |
| API enabled | yes | yes |
| Entitlement is a template | exists, folder policy unchanged | confirmed |
| Requester &ne; approver | different principals | confirmed, asserted by the script |
| Subject holds nothing directly | no bindings | none |
| Access before the grant | refused | `does not have permission` |
| Access during the grant | permitted | policy returned |
| Binding source | written by PAM, not Terraform | confirmed |
| Access after expiry | refused again | identical error |
| **Expiry lag** | measured, not assumed | see below |

### Capture figure 04 before approving

The `APPROVAL_AWAITED` state is **perishable**. Approving destroys it, and
retaking that figure costs another 30-minute cycle plus another human approval.
`request-grant.sh` prints a reminder for exactly this reason.

---

## 6. Troubleshooting

### `PAM has not been enabled for this resource`

**Cause.** The API is enabled; the resource is not onboarded. Different things.

**Fix.** §2 — grant the org-scoped PAM service agent
`roles/privilegedaccessmanager.folderServiceAgent` on the folder.

### HTTP 404 with an HTML body

**Cause.** The `parent` carried the `folders/` prefix twice, producing a request
to `/v1/folders/folders/NNN/locations/global/entitlements`.

**Fix.** The variable already holds `folders/NNNN`; use it as-is. Google answers
a malformed path with a generic HTML 404 — **no field named, no hint the path
was wrong** — so read the URL in the error rather than the message.

### `invalid_grant` — the issuer does not match

```
The issuer in ID Token https://app.terraform.io does not match the expected
one in config: https://token.actions.githubusercontent.com
```

**Cause.** The workspace pointed at the **GitHub Actions** provider. This
project has two workload identity pools, `github` and `hcp-terraform`, and a
derivation that took the first match got the wrong one.

**Fix.** Select by issuer, not by position:

```bash
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=hcp-terraform --location=global \
  --format='table(name.basename(),oidc.issuerUri)'
```

**One item is not evidence of uniqueness**, the same way Week 01's zero items
were not evidence of absence.

### A clean plan, then an apply that cannot authenticate

**Cause.** The first plan ran against **empty state** with nothing to refresh,
so it never called Google at all. It proved the configuration parses, not that
the credentials work.

**Lesson.** Week 03 phrased it as "a clean plan is not evidence the apply will
work". This is the stronger form: a plan over empty state does not even
exercise authentication.

### `json.decoder.JSONDecodeError: Extra data`

**Cause.** A helper concatenated `stdout` and `stderr`. gcloud writes progress
lines such as `Parsed [entitlement] resource: ...` to stderr, so every
`--format=json` reply came back with prose stapled on.

**Fix.** Return them separately. This crash lost 25 minutes of a 30-minute
measurement window, which could only be reopened by asking a human to approve
another grant.

### The expiry reference is not in the timeline

**Cause.** `timeline.events[].requested.expireTime` is when the **request**
lapses if nobody approves it — 24 hours out — not when the grant ends.

**Fix.** `auditTrail.accessGrantTime + requestedDuration`.

### The console shows "No entitlements" for an entitlement that exists

**Cause.** The Entitlements page defaults to **My Entitlements**, which lists
what *you* may request. An approver who is not also a requester sees nothing.

**Fix.** Switch to **Entitlements for all users**.

---

## 7. Known limitations

- **IAM Recommender is not in this week.** Role recommendations for non-basic
  roles, custom-role suggestions and policy insights require Security Command
  Center **Premium or Enterprise**. Every grant in this lab is a predefined
  role, so the free tier would report nothing. This week demonstrates the
  mechanism and makes **no claim** that the estate needed it.
- **Single-approver workflow.** Multi-level and multi-party approvals are
  Preview and also require Premium/Enterprise. Requester and approver are
  different principals here, which is the honest version available on the free
  tier, but it is one person's judgement rather than a quorum.
- **One entitlement, one role, one folder.** Nothing here tests overlapping
  entitlements, conditions on the granted role, or what happens when two grants
  are active at once.
- **The operator holds `privilegedaccessmanager.admin` on the folder**, granted
  out of band so grants can be approved at all. It is in the cleanup list.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Approvals | Multi-party approval, so elevation is never one person's decision |
| Scope | One entitlement per task, not per role — "read IAM policies during an incident" rather than a role name |
| Detection | Pair with IAM Recommender to find standing grants that should become entitlements; that needs SCC Premium |
| Alerting | Alert on every grant request and approval. A grant nobody notices is a standing role with extra steps |
| Duration | Request far less than the 30-minute floor where the task allows — it is a ceiling, and requesters may ask for less |

---

## 9. References

- [Privileged Access Manager overview](https://docs.cloud.google.com/iam/docs/pam-overview)
- [Create entitlements](https://docs.cloud.google.com/iam/docs/pam-create-entitlements)
- [Request temporary elevated access](https://docs.cloud.google.com/iam/docs/pam-request-temporary-elevated-access)
- [Approve or deny grants](https://docs.cloud.google.com/iam/docs/pam-approve-deny-grants)
- [PAM roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/privilegedaccessmanager)

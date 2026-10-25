# Lab Guide — Week 09: Service Account Lifecycle

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-09-sa-lifecycle/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-10-14. **Deliberately still running** —
see §6.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with at least two projects that have the Compute Engine API enabled, so default service accounts exist |
| Apply identity | `roles/iam.serviceAccountAdmin` and `roles/orgpolicy.policyAdmin` at the organization |
| Operator | `roles/iam.securityReviewer` or equivalent, to read last-authentication data |
| APIs | `policyanalyzer.googleapis.com` and `orgpolicy.googleapis.com` on the quota project |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

**Cross-week:** Week 1 supplies the projects whose default service accounts this
lab disables. Week 2 supplies keyless CI, which is convenient but not required.

**Region:** none; everything here is global.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive**, from `terraform.tfvars` |
| `logging_project_id` | first project whose default SAs are disabled |
| `security_project_id` | second project whose default SAs are disabled |

---

## 3. Find out which accounts are actually unused

**Do this before writing any Terraform.** The whole lab depends on knowing which
identities have never been used, and the answer is not guessable.

```bash
gcloud policy-intelligence query-activity \
  --activity-type=serviceAccountLastAuthentication \
  --project=<PROJECT_ID> --format=json
```

**Actual result, 2026-10-14:**

| Service account | Last authenticated |
| --- | --- |
| `finops-reader@…` | 2026-10-09 |
| `tf-plan@…` | 2026-10-05 |
| `tf-apply@…` | 2026-10-05 |
| `<project-number>-compute@developer…` | **never** |
| `<project-number>-compute@developer…` | **never** |

`finops-reader` looked dormant and was not — it had authenticated five days
earlier. **Measure; do not reason about which accounts look idle.**

---

## 4. Deploy

```bash
cd week-09-sa-lifecycle/terraform
terraform init
terraform plan      # expect: 3 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

| Resource | Purpose |
| --- | --- |
| `google_project_default_service_accounts` ×2 | `action = "DISABLE"`, `restore_policy = "REVERT"` |
| `google_org_policy_policy` | `iam.disableServiceAccountKeyCreation` on the **legacy** constraint generation |

**Why DISABLE and not DELETE.** Google's guidance is to disable first and
confirm nothing breaks. The irreversibility is not what people assume: a deleted
service account's email **can** be reused, but IAM tracks an internal unique ID,
so role bindings that referred to the deleted account never apply to a recreated
one with the same address. A rebuild looks identical and is not.

**Why the legacy constraint too.** See §7 — this is the week's trap.

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-10-14 |
| --- | --- | --- |
| Default SAs disabled in both projects | `disabled = True` | both disabled |
| Still present, not deleted | account resolves | both present |
| Key creation blocked on **both** constraint generations | `enforce: True` on each | both enforced |
| No user-managed keys org-wide | zero | zero |
| Accounts kept are the ones in use | reported, not asserted | 3 in use, 2 disabled |

The last row is deliberately a **report**, not a pass/fail: an account idle today
may be seasonal, and a check that failed on that would train people to ignore it.

**Nothing broke after the disable.** Weeks 06–08 validators still passed. That is
terminal output rather than a picture, which is why there is no figure for it.

---

## 6. Cleanup

**This week is exempt from teardown, deliberately.** Disabling an unused identity
is the desired end state, not a temporary demonstration, and it costs nothing.

If you do destroy it, `restore_policy = "REVERT"` returns the accounts to their
prior state — so a destroy **re-enables** them. That is the right default for a
lab and the wrong one for a real cleanup; if you intend the accounts to stay
disabled, remove the resource from state rather than destroying it:

```bash
terraform state rm google_project_default_service_accounts.logging
```

**Verify the current state at any time:**

```bash
gcloud iam service-accounts list --project=<PROJECT_ID> \
  --filter="email~compute@developer" --format="value(email,disabled)"
```

**Cost:** $0, during and after.

---

## 7. Troubleshooting

### The key-creation constraint appears to be switched off

**Symptom.** `gcloud org-policies describe
iam.disableServiceAccountKeyCreation --organization=<ORG> --effective` returns
`enforce: false`, which reads as "the lab's first rule is not enforced".

**Cause.** Organization policy constraints exist in two generations. The
**managed** generation, `iam.managed.disableServiceAccountKeyCreation`, was
enforced by Google's baseline all along. The legacy constraint of the same name
had **no policy at all**, and absent evaluates identically to switched off.

**Resolution.** Check both generations before concluding anything:

```bash
for C in iam.disableServiceAccountKeyCreation \
         iam.managed.disableServiceAccountKeyCreation; do
  gcloud org-policies describe "$C" --organization=<ORG> --effective \
    --format="value(spec.rules[0].enforce)"
done
```

This lab then sets the legacy one too — redundant while the baseline holds,
which is what defence in depth means, and it removes the trap for whoever checks
next.

**Lesson.** A constraint reading `false` may mean "not set on this generation"
rather than "not enforced". This nearly produced a confident, wrong security
alarm.

### An account that looks dormant is not

**Symptom.** An identity with no recent activity in the console.

**Cause.** The console view is not last-authentication data.

**Resolution.** Query Activity Analyzer, as in §3. `finops-reader` had
authenticated five days before it was assessed.

**Lesson.** Never reason about which accounts look idle. Ask.

---

## 8. Known limitations

- **Last-authentication data has a lag and a window.** Google reports service
  account insights for accounts that have not authenticated in the past 90 days.
  "Never authenticated" is the safe signal to act on; "quiet for a month" is not.
- **This lab disables, it does not delete.** Whether the accounts should
  eventually be deleted is left open on purpose — the unique-ID behaviour in §4
  makes deletion the one genuinely irreversible step.
- **Scope.** Only the two projects named in the variables. Other projects in the
  organization still have enabled default service accounts.

---

## 9. For production

| Area | What would change |
| --- | --- |
| Coverage | Run the last-authentication query across every project on a schedule, not once by hand |
| Enforcement | Add `iam.automaticIamGrantsForDefaultServiceAccounts` if the baseline does not already set it — that automatic Editor grant is what usually makes a default SA dangerous |
| Lifecycle | Define a documented interval between disable and delete, and alert on re-enablement |
| Evidence | Keep the last-authentication output as an audit artifact, not only as a one-off reading |

---

## 10. References

- [Service accounts overview](https://docs.cloud.google.com/iam/docs/service-account-overview) — disable before delete; the unique-ID behaviour
- [Activity Analyzer: recent usage](https://docs.cloud.google.com/iam/docs/service-account-recent-usage)
- [Service account insights](https://docs.cloud.google.com/iam/docs/manage-service-account-insights)
- [Terraform `google_project_default_service_accounts`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_default_service_accounts)

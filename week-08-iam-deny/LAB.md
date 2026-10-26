# Lab Guide — Week 08: IAM Deny Policies and Custom Roles

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-08-iam-deny/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-10-05. Still running — see §6.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with an existing over-grant to take back (Week 07 supplies one) |
| Apply identity | `roles/iam.organizationRoleAdmin` (custom roles) and `roles/iam.denyAdmin` (deny policies), both at the organization |
| Operator | `roles/iam.denyReviewer` to read deny policies; a quota project for Policy Troubleshooter |
| APIs | `iam.googleapis.com`, `policytroubleshooter.googleapis.com` on the quota project |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

**Cross-week:** Week 07 granted the plan identity `roles/cloudasset.owner`
because no read-only role could read an asset feed. This lab takes that back.
Without Week 07 you have nothing to narrow, so create an equivalent over-grant
first or pick your own.

**Region:** none; organization-scoped.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive** |
| `plan_service_account` | the identity being narrowed |
| `apply_service_account` | exempted from the deny, because it manages the feed |
| `break_glass_principal` | a human exempted from the deny — **sensitive** |

---

## 3. Deploy

```bash
cd week-08-iam-deny/terraform
terraform init
terraform plan      # expect: 3 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

| Resource | Purpose |
| --- | --- |
| `google_organization_iam_custom_role` | `tfPlanAssetReader` — exactly two permissions |
| `google_organization_iam_member` | binds the custom role to the plan identity |
| `google_iam_deny_policy` | `deny-asset-feed-deletion`, with two exceptions |

### The two things that will bite you

**Deny policies use IAM v2 principal identifiers**, which are not the member
strings used everywhere else in Terraform:

| Principal | v2 identifier |
| --- | --- |
| service account | `principal://iam.googleapis.com/projects/-/serviceAccounts/<email>` |
| human | `principal://goog/subject/<email>` |
| everyone | `principalSet://goog/public:all` |

Using the allow-policy spelling fails with *"invalid principal … as part of the
exempted principals list"*.

**The exception list is not optional.** Deny beats allow, including for
Organization Admin. A deny with no way out gets deleted wholesale the first time
someone needs the denied action under pressure — which removes the guardrail
entirely instead of using it once.

---

## 4. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-10-05 |
| --- | --- | --- |
| Custom role carries only the two read permissions | `feeds.get`, `feeds.list`, nothing else | exactly two |
| The Week 07 over-grant is gone | no `cloudasset.owner` for the plan identity | removed |
| Deny policy exists and exempts the right two | apply identity + break-glass human | both present |
| Plan identity may **not** delete a feed | `CANNOT_ACCESS` | `CANNOT_ACCESS` |
| Plan identity may still read one | `CAN_ACCESS` | `CAN_ACCESS` |
| Apply identity may still manage one | `CAN_ACCESS` | `CAN_ACCESS` |

**Use Policy Troubleshooter v3.** `gcloud policy-troubleshoot iam` calls **v1**,
which evaluates allow policies only — with a deny policy actively blocking the
permission, v1 answered `GRANTED`. A check built on it passes while the control
it is checking does nothing.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: <QUOTA_PROJECT>" \
  -H "Content-Type: application/json" \
  "https://policytroubleshooter.googleapis.com/v3/iam:troubleshoot" \
  -d '{"accessTuple":{"principal":"<SA_EMAIL>","fullResourceName":"//cloudresourcemanager.googleapis.com/organizations/<ORG_ID>","permission":"cloudasset.googleapis.com/feeds.delete"}}'
```

Read the deny policy itself over **IAM v2 REST**, not `gcloud iam policies
describe` — the gcloud form returned nothing for an organization attachment
point, and the list endpoint returns names without rules. Only the GET shows the
exceptions, which are the part worth checking.

---

## 5. Cleanup

```bash
terraform destroy
```

**Verify removal:** the deny policy should 404 from the v2 GET, and
`gcloud iam roles describe tfPlanAssetReader --organization=<ORG_ID>` should
report the role deleted.

**Note:** destroying re-opens the gap Week 07 created — the plan identity loses
the narrow custom role and, if you also restore the old binding, regains
`cloudasset.owner`. Decide deliberately which state you want.

**Cost:** $0. Custom roles, deny policies and Policy Troubleshooter are all
free.

---

## 6. Troubleshooting

### `invalid principal … as part of the exempted principals list`

**Cause.** Allow-policy member strings (`serviceAccount:…`, `user:…`) in a deny
policy. Deny policies use IAM v2 identifiers.

**Fix.** Use the table in §3.

### Policy Troubleshooter says GRANTED while the deny is active

**Cause.** `gcloud policy-troubleshoot iam` calls v1, which cannot see deny
policies at all.

**Fix.** Call v3 directly. Measured 2026-10-05: with the deny in force, v1
reported `GRANTED` and v3 reported `CANNOT_ACCESS` for the same tuple.

**Lesson.** An instrument that cannot observe the control you are testing will
confirm whatever you hoped.

### Creating a custom role fails with a permission error

**Cause.** `roles/iam.organizationRoleAdmin` is needed to create one, and
`roles/iam.organizationRoleViewer` to read one back. The failure was not the
create — it was the read-back during refresh.

---

## 7. Known limitations

- **One permission, one resource type.** The deny covers
  `cloudasset.googleapis.com/feeds.delete` only. It is a demonstration of the
  mechanism, not a complete guardrail set.
- **The break-glass exception is a named human.** That is deliberate, and it is
  also a single point of failure: if that person is unavailable, the denied
  action cannot be performed without editing the policy.
- **Policy Troubleshooter v3 is the only instrument used.** No independent
  confirmation from audit logs that a real delete attempt was refused — the
  validation is an evaluation, not an observed denial.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Coverage | Deny the destructive verbs across the services that matter, not one |
| Break-glass | A group rather than a named person, with membership alerting |
| Evidence | Attempt the denied action and capture the audit log entry, rather than relying on evaluation alone |
| Review | Deny policies are invisible to most IAM tooling; add them to access reviews explicitly |

---

## 9. References

- [Deny policies](https://docs.cloud.google.com/iam/docs/deny-overview)
- [Principal identifiers for deny policies](https://docs.cloud.google.com/iam/docs/principal-identifiers)
- [Policy Troubleshooter](https://docs.cloud.google.com/policy-intelligence/docs/troubleshoot-access)
- [Custom roles](https://docs.cloud.google.com/iam/docs/creating-custom-roles)
- [Terraform `google_iam_deny_policy`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_deny_policy)

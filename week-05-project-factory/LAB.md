# Lab Guide — Week 05: Project Factory and a Custom Constraint

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-05-project-factory/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-09-19. Still running.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with a folder to create projects into |
| Billing account | with a **free project slot** — see §7, this is the real limit |
| Apply identity | `roles/resourcemanager.projectCreator`, `roles/resourcemanager.tagAdmin`, `roles/resourcemanager.tagUser`, `roles/essentialcontacts.admin`, `roles/orgpolicy.policyAdmin`, all at the organization |
| Quota project | with `cloudresourcemanager`, `serviceusage`, `cloudbilling` and `essentialcontacts` enabled |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

**Cross-week:** Week 1 supplies the folder hierarchy. Week 2 supplies keyless
CI. Week 3's org policy machinery is reused for the custom constraint.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive** |
| `billing_account` | billing account to link — **sensitive** |
| `parent_folder_id` | folder the new project lands in |
| `project_prefix` | enforced by the custom constraint |

---

## 3. Deploy

```bash
cd week-05-project-factory/terraform
terraform init
terraform plan      # expect: 11 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 11 added, 0 changed, 0 destroyed.`

| Where | Resources | Purpose |
| --- | --- | --- |
| root | 4 | tag key, two tag values, the custom constraint |
| `modules/project` | 5 | the project, its labels, tag binding, essential contacts, API enablement |

### Four roles for what looks like one job

| Action | Role |
| --- | --- |
| create the project | `resourcemanager.projectCreator` |
| create the tag key and values | `resourcemanager.tagAdmin` |
| **bind** a tag to the project | `resourcemanager.tagUser` |
| set essential contacts | `essentialcontacts.admin` |

**Creating a tag and binding a tag are different roles.** `tagAdmin` creates
keys and values and carries no `tagValueBindings.create`. Same create-versus-attach
split as Week 04's firewall policy roles.

**Creating a project confers no right to administer its contacts.**

---

## 4. The custom constraint, and what it can actually read

```
resource.projectId.startsWith(prefix) && resource.parent.startsWith("folders/")
```

**Deployed in DRY RUN.** It reports violations without denying anything.

### Which fields a Project resource exposes — measured by probing

| Field | Result |
| --- | --- |
| `resource.projectId` | **accepted** |
| `resource.parent` | **accepted** |
| `resource.labels` | **rejected** |
| `resource.displayName` | **rejected** |

The rejection is `Error 400: Request has invalid values`, naming nothing. The
supported-services reference lists Project at Preview and never publishes its
fields.

**Probe before designing a constraint on an unfamiliar resource.** A constraint
written against `resource.labels` looks correct and fails at apply time with an
error that names neither the field nor the reason.

---

## 5. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-09-19 |
| --- | --- | --- |
| The project the factory built | exists, correct parent | present, in `workloads/dev` |
| Labels | `week`, `env`, `managed-by` | all three |
| Environment tag | bound, value `dev` | bound |
| Essential contacts | SECURITY and TECHNICAL | both set |
| No default network | zero VPCs | none created |
| The naming constraint | dry run, readable fields only | dry run, two fields |

---

## 6. Cleanup

```bash
terraform destroy
```

**Careful — this is where it bites.** An enforced constraint can make a resource
un-reconcilable with its own configuration. Destroying Week 04's spoke failed
first because Terraform wanted to remove `block-project-ssh-keys` metadata added
during testing, and the by-then-enforced constraint refused the removal.

**Verify:** the project should report `DELETE_REQUESTED`, and the tag key should
be gone. A deleted project holds its billing slot for 30 days.

**Cost:** $0. A project, a tag key with two values, an essential contact and a
custom constraint are all free.

---

## 7. Troubleshooting

### `Error 400: Request has invalid values` on the custom constraint

**Cause.** The CEL expression references a field the Project resource does not
expose — `resource.labels` or `resource.displayName`.

**Fix.** Use `resource.projectId` and `resource.parent`. Probe first; the
documentation does not list the fields.

### Tag binding fails with a permission error after the project is created

**Cause.** `tagAdmin` creates tags; `tagUser` binds them. Holding the first does
not imply the second.

### `Cloud billing quota exceeded`

**Cause.** The billing account caps linked projects. This lab hit the limit at
**five**.

**Fix.** Unlink an unused project — and note that **only the owning identity can
unlink a project outside the organization**; an organization admin cannot. A
deleted project continues to hold its slot for 30 days.

**Lesson.** The real limit on a project factory is not Terraform or IAM, it is a
billing quota, and it is the constraint most likely to stop a later week.

---

## 8. Known limitations

- **The constraint is in dry run.** It denies nothing. Promoting it would not
  retroactively fix the two projects already sitting outside a folder (found in
  Week 07).
- **One project, built once.** A factory that has produced a single project is a
  module, not yet a factory; concurrency and naming collisions are untested.
- **Five linked projects is the ceiling** on this billing account, which makes
  repeated runs impossible without unlinking something.

---

## 9. For production

| Area | What would change |
| --- | --- |
| Enforcement | Promote the constraint out of dry run, with a remediation plan for existing violations |
| Quota | Request a higher linked-project limit before relying on a factory |
| Inputs | Validate the project prefix and parent in the module, not only in the org policy, so failures surface at plan time |
| Lifecycle | Decide deliberately what happens to a project on destroy — the 30-day slot hold is a real operational constraint |

---

## 10. References

- [Creating and managing projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects)
- [Custom organization policy constraints](https://docs.cloud.google.com/resource-manager/docs/organization-policy/creating-managing-custom-constraints)
- [Tags overview](https://docs.cloud.google.com/resource-manager/docs/tags/tags-overview)
- [Essential Contacts](https://docs.cloud.google.com/resource-manager/docs/managing-notification-contacts)

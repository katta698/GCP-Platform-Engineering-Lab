# Lab Guide — Week 03: Organization Policy Guardrails

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-03-org-policy-guardrails/)
explains what it does and why; this guide is the runbook.

**Status:** deployed 2026-09-03 in dry run; the three managed constraints were
promoted to enforce in Week 04 once there was a Compute resource to evaluate.
Still running.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with a folder hierarchy (Week 1) |
| Apply identity | `roles/orgpolicy.policyAdmin` at the organization |
| Operator | `roles/logging.viewer` at the organization, to read dry-run violations |
| APIs | `orgpolicy.googleapis.com` **and** `logging.googleapis.com` on the quota project |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

**A clean plan is not evidence the apply will work.** Writing org policy needs
`orgpolicy.googleapis.com` enabled on the quota project; *reading* it does not.
The plan only reads, so it passes and the apply fails with `SERVICE_DISABLED`.

---

## 2. Before writing anything: read what is already enforced

```bash
gcloud org-policies list --organization=<ORG_ID> --show-unset
gcloud org-policies describe <CONSTRAINT> --organization=<ORG_ID> --effective
```

**`gcloud org-policies list` does not show what is enforced.** It shows what is
explicitly **set**. A managed constraint can be fully enforced by a Google
*default* that appears in neither `list` nor plain `describe` — only
`--effective` reveals it.

**Measured 2026-09-03:** this organization already had **seven enforced
constraints** from Google's security baseline, all sharing an `updateTime` from
the moment the organization was created. `list` showed 12 policies; the console
showed 26. One constraint was added to this lab as a "new guardrail" and turned
out to be enforced already.

`--effective` is also the only place a managed constraint's **parameter schema**
is visible — Google documents what the parameterised constraints do without
publishing their fields.

---

## 3. Deploy

```bash
cd week-03-org-policy-guardrails/terraform
terraform init
terraform plan      # expect: 8 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`

| Resource | State at deploy |
| --- | --- |
| `compute.managed.requireOsLogin` | dry run |
| `compute.managed.blockProjectSshKeys` | dry run |
| `compute.managed.disableSerialPortAccess` | dry run |
| `custom.requireTerraformLabelsOnBuckets` | dry run |
| the custom constraint definition | — |
| exception at `workloads/dev` | `enforce = FALSE` for serial port |
| 2 × API enablement | — |

### Chain the policies with `depends_on`

**The Organization Policy API serializes changes per parent.** Terraform's
default parallelism of 10 produces HTTP 409 `CONCURRENT_POLICY_CHANGES`,
partially and non-deterministically.

The CLI fix is `-parallelism=1`. **HCP Terraform refuses it** — *"Custom
parallelism values are currently not supported."* On remote execution the
ordering has to be an edge in the dependency graph, so the resources are chained
with `depends_on`. This applies to every later week that writes several policies
to one parent.

---

## 4. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-09-03 |
| --- | --- | --- |
| Every policy set on the organization | enumerated | 12 set, 26 effective |
| This week's four, and each one's state | all dry run | all dry run |
| The custom constraint's definition | CEL expression present | present |
| The deliberate exception at `workloads/dev` | `enforce = FALSE` | present |
| The constraint tested against a real request | a violation is logged | logged |

**`validate.sh` waits 120 seconds** before testing a constraint. Enforcement
lags the write by **75–100 seconds**, and un-enforcement by **77–108 seconds**,
measured over three trials with `scripts/measure-enforcement-lag.py`.
`describe --effective` reports `enforce: true` for the whole window, so the API
says the policy is in force well before it is.

### Where dry-run violations actually land

**In the PROJECT audit log**, as `OrgPolicyDryRunAuditMetadata` carrying
`dryRunResult` and `liveResult`. The organization-level
`cloudaudit.googleapis.com%2Fpolicy` stream does not exist here, and querying it
returns empty **without an error** — which reads exactly like "no violations".

The record carries `status.code 7 POLICY_VIOLATED` on a request that
**succeeded**. Anything alerting on `status.code != 0` will report an outage that
is not happening.

---

## 5. Cleanup

```bash
terraform destroy
```

Then, out of band, remove the operator's organization-level
`roles/logging.viewer` if it is no longer needed — `scripts/cleanup.sh` has the
command. It was granted by hand so dry-run violations could be read.

**Cost:** $0. Organization policy is free.

---

## 6. Troubleshooting

### `SERVICE_DISABLED` after a clean plan

**Cause.** Writing org policy needs `orgpolicy.googleapis.com` on the quota
project; reading it does not, and a plan only reads.

**Fix.** Enable it before the apply, not during.

### HTTP 409 `CONCURRENT_POLICY_CHANGES`

**Cause.** The API serializes changes per parent; Terraform's default
parallelism is 10.

**Fix.** `depends_on` chains on remote execution. `-parallelism=1` works on the
CLI and is rejected by HCP.

### A constraint reports enforced and still permits the action

**Cause.** Enforcement lag, 75–100 seconds. The reverse lag — 77–108 seconds —
is the operationally dangerous one: disable a guardrail during an incident, see
the apply go green, retry, still get refused, and conclude wrongly that the
change failed.

**Fix.** Wait. Do not re-apply.

### A lag-measurement script that leaves the organization degraded

**Cause.** The first version crashed mid-cycle having already flipped a
constraint back to dry run, and left the organization in a state the published
post contradicted.

**Fix.** Restore the control in a `finally` block, never on the happy path. The
crash itself was trivial — `subprocess` cannot launch bare `gcloud` on Windows
because it is a `.CMD` shim and `CreateProcess` does not apply `PATHEXT`;
resolve with `shutil.which`.

### There is no `gcloud org-policies list-constraints`

The v2 surface has no verb for enumerating constraints. Discovery is the
`--show-unset` flag on `list`. gcloud's "Maybe you meant" suggests three wrong
commands and never mentions it. This organization: 196 constraints, 60 managed.

---

## 7. Known limitations

- **Deployed in dry run, so nothing was denied at deploy time.** The three
  managed constraints were promoted in Week 04, once a Compute resource existed
  to evaluate. The custom bucket-label constraint was promoted separately.
- **A dry-run constraint with no matching resources produces no violations**,
  which is indistinguishable from a constraint that works. That is why these sat
  unpromoted until Week 04.
- **One exception, at one folder.** `workloads/dev` overrides the serial-port
  constraint; whether that exception is still justified is not re-reviewed
  anywhere.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Promotion | A documented path from dry run to enforce, with violation evidence required before promotion |
| Alerting | Alert on `dryRunResult` in the project audit log — and **not** on `status.code != 0`, which fires on successful requests |
| Exceptions | Review folder-level exceptions on a schedule; an exception with no expiry is a permanent hole |
| Baseline | Read `--effective` before adding any constraint, or you will re-add one Google already enforces |

---

## 9. References

- [Organization policy constraints](https://docs.cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints)
- [Managed constraints](https://docs.cloud.google.com/resource-manager/docs/organization-policy/understanding-managed-constraints)
- [Custom constraints](https://docs.cloud.google.com/resource-manager/docs/organization-policy/creating-managing-custom-constraints)
- [Dry-run policies](https://docs.cloud.google.com/resource-manager/docs/organization-policy/dry-run-policy)

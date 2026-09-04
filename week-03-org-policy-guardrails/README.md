# Week 03 — Organization policy and guardrails

Status: ✅ **Complete 2026-09-03.** Three managed constraints in dry run; the custom constraint promoted to enforced and its denial proven.

## Cost note

**Zero.** This week creates no billable resource — organization policy is
metadata on the resource hierarchy, not infrastructure. Two APIs are enabled on
the seed project (`orgpolicy`, `logging`); enabled APIs cost nothing on their own,
and log storage for this volume sits inside the free tier.

`scripts/cleanup.sh` exists for correctness rather than cost. There is nothing
here worth tearing down to save money, and the week is safe to leave running
indefinitely.

## What this week is actually about

Not "turn on some guardrails". This organization was never empty: it inherited
**seven enforced constraints** at creation, all carrying the same `updateTime` to
within a fraction of a second — one batch applied by Google, not a set that
accumulated. Week 02 was built on two of them.

So the work is: find out what the platform already decided, add only what it did
not, and prove each addition is safe before it can deny anything.

Three properties of the Organization Policy Service drive every decision:

1. **Policy inherits downward and the closest policy wins.** A folder's policy
   replaces the organization's for everything beneath it. It does not merge, and
   it does not have to be stricter.
2. **A policy written at the organization on an already-set constraint replaces
   that spec.** Hardening and loosening are the same API call with different
   contents.
3. **A dry-run spec is evaluated on every request and logged when it would have
   denied, while denying nothing.** That is what makes it possible to find out
   what a constraint breaks before it breaks it.

## What was deployed

Four policies at the organization, all dry-run, plus one deliberate exception.

| Constraint | Type | Why |
| --- | --- | --- |
| `compute.managed.requireOsLogin` | managed | VM access goes through IAM, not keys pasted into metadata |
| `compute.managed.blockProjectSshKeys` | managed | A project-wide key must not silently grant access to VMs that do not exist yet |
| `compute.managed.disableSerialPortAccess` | managed | The serial console is a path in that no network control observes |
| `custom.requireTerraformLabelsOnBuckets` | **custom** | This lab's own labelling rule, enforced by the platform instead of by a reviewer |

**The exception:** `workloads/dev` overrides the serial-port constraint with
`enforce = FALSE`. The thing the constraint defends against and the thing dev
genuinely needs are the same thing — a way to see a machine too broken to reach
over the network. Written down at the narrowest node, because the alternative is
the first engineer with an unbootable dev VM asking for it to be turned off *at
the organization*, where it was set.

Everything is written on the **v2** resources. The v1 `google_organization_policy`
cannot express a `.managed.` constraint at all
([provider issue #21401](https://github.com/hashicorp/terraform-provider-google/issues/21401)),
so using legacy constraint names would not be a style choice — it would teach the
retiring API.

## Measured findings

Every number here came from this deployment.

**A clean plan is not evidence the apply will work.** `terraform plan` reported
`7 to add` and the apply immediately failed with `SERVICE_DISABLED` on
`orgpolicy.googleapis.com`. Reading organization policy requires no API enabled —
the seven baseline constraints listed fine. The dependency appears at the first
*write* and nowhere earlier.

**The Organization Policy API serializes changes per parent.** Terraform's default
parallelism of 10 produced HTTP 409 `CONCURRENT_POLICY_CHANGES`, partially and
non-deterministically — the first attempt landed two of four policies before
failing. The CLI answer is `-parallelism=1`, and HCP Terraform refuses it:
*"Custom parallelism values are currently not supported."* On remote execution
there is no flag to reach for, so the ordering has to be an edge in the
dependency graph. The constraint forced the better fix: a property of the code
rather than an operator's memory.

**`gcloud org-policies list` does not show what is enforced.** It shows what is
explicitly *set*. A managed constraint can be fully enforced by a Google default
that appears in neither `list` nor plain `describe` — only `--effective` reveals
it. `iam.managed.disableServiceAccountApiKeyCreation` was added to this week as
an "addition", then removed once `--effective` showed it already enforced with
`parameters.allowedServices` exempting the Gemini API. The console had said so
all along: **26 active organization policies** against `list`'s **12**.

That mistake paid for itself twice — `--effective` also prints the parameter
*schema* of a managed constraint, which the reference documentation describes
without publishing.

**What a dry-run violation looks like.** An unlabelled bucket was created while
the custom constraint was in dry run. The request succeeded, and produced:

```json
"metadata": {
  "@type": "type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata",
  "constraint": "customConstraints/custom.requireTerraformLabelsOnBuckets",
  "dryRunResult": "DENIED",
  "liveResult": "ALLOWED"
},
"status": { "code": 7, "message": "POLICY_VIOLATED" }
```

Two traps in that record. The status reads `POLICY_VIOLATED` with gRPC **code 7
(PERMISSION_DENIED) on a request that succeeded** — anything alerting on
`status.code != 0` will report an outage that is not happening. And the entry
lands in the **project's** audit log, not an organization-level policy stream:
querying the organization returns nothing *and no error*, which is
indistinguishable from "no violations occurred".

**Enforcement is not instant, and the effective policy lies about it.** The first
denial attempt succeeded — a bucket was created about a minute after the flip,
while `describe --effective` already read `enforce: true`. The same request was
refused roughly two minutes later. A validation script that tests immediately
after an apply will report a working constraint as broken, and the natural
conclusion — that the constraint is wrong — sends you editing correct code.

**The denial, once it landed:**

```
ERROR: HTTPError 412: orgpolicy:projects/_/buckets/... violates
customConstraints/custom.requireTerraformLabelsOnBuckets.
Details: Storage buckets must carry the three labels this lab requires...
```

**412 Precondition Failed**, not 403 — and the `description` written in Terraform
is quoted back to whoever hits it. That is the argument for writing that field
for the person who will be stopped by it rather than as a change-log entry.

**The rule cannot be satisfied by the tool that trips it.** `gcloud storage
buckets create` has **no label flag at all**, so the compliant request had to go
through the JSON API. Worth knowing before enforcing a label constraint
organization-wide.

## Order of work

1. `ORG_ID=... ./scripts/read-current-policy.sh` — **with `--effective`**, before writing anything
2. `./scripts/deploy.sh` — remote apply as `tf-apply`, everything lands in dry run
3. Read the dry-run violations out of the project audit log
4. Promote **one** constraint at a time via the `enforce` map, and apply again
5. `ORG_ID=... SEED_PROJECT=... DEV_FOLDER_ID=... ./scripts/validate.sh`

Allow a few minutes between step 4 and step 5. Enforcement lags the policy write,
and validating too early produces a confident false negative.

Step 4 is the week's method. Flipping the set together works and gives up the
only thing dry run was for.

## Evidence

- `docs/blog/screenshots/` — console and HCP captures, identifiers redacted
- `docs/blog/evidence-terminal.md` — terminal output that reached no HCP run log,
  including the parallelism refusal, which is not reproducible once the
  configuration is fixed
- `docs/references.md` — what each source settled, and where the documentation
  did not answer the question

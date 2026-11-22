# Cost guardrails — what refuses, what only alerts, and what neither does

Built 2026-11-22. Every claim here was tested against the live organization,
and the tests are reproducible with `scripts/prove_guardrails.sh`.

## The audit: what existed before

| Control | Present | Blocks spend, or only alerts? |
| --- | --- | --- |
| Budgets — "GCP lab guardrail" and "— programmatic", $25/mo each, 50/90/100% | yes | **Alerts only.** Google Cloud does not stop spending when a budget is exceeded. `terraform/bootstrap/main.tf` says so in its own comment |
| Org policies, 11 enforced | yes | **Block** — but every one is security: SSH keys, OS Login, service account keys, uniform bucket access. **None was about cost** |
| Custom constraints, 2 | yes | **Block** — project naming, bucket labels. Not cost |
| IAM deny policies (Week 08) | yes | **Block by permission, never by price** |
| Quotas | defaults | **Block**, but the defaults permit far more than $25/month |
| AWS-style Service Control Policies | n/a | GCP has no SCP. The equivalents are Org Policy and IAM deny, both above |

**Before this document, nothing in the lab refused an expensive resource.** The
only cost control was an alert that arrives after the money is spent.

## What was built

All three live in `terraform/bootstrap/guardrails.tf`, at the **organization**,
applied once and never torn down. A week folder's `terraform destroy` cannot
remove them — which is not hypothetical: the Week 06 budget was destroyed with
its week, and that is why only the bootstrap budget survives.

### 1. VM size — PROVEN TO REFUSE

`custom.restrictMachineTypesToSmall`, ALLOW on `compute.googleapis.com/Instance`
for CREATE and UPDATE. Allowed: e2-micro, e2-small, e2-medium, f1-micro,
g1-small.

Attempted `n2-standard-8` (~$0.39/hr):

    ERROR: (gcloud.compute.instances.create) Could not fetch resource:
     - Operation denied by org policy:
       [customConstraints/custom.restrictMachineTypesToSmall] :
       A lab VM is an instrument, not a workload.
       Allowed: e2-micro, e2-small, e2-medium, f1-micro, g1-small.

And the control, which matters as much: `e2-micro` was still created
successfully, so the guardrail refuses the expensive case without breaking the
lab's normal work.

### 2. Cloud SQL tier — DEFINED, NOT YET PROVEN

`custom.restrictCloudSqlToSmallTiers`, ALLOW on `sqladmin.googleapis.com/Instance`,
permitting `db-f1-*`, `db-g1-*` and `db-custom-1-3840`.

**Untested.** The Cloud SQL Admin API is not enabled on any lab project, so the
attempt failed before reaching the policy. Enabling an API purely to test it
was not worth doing; this will be proven on Week 36, which is when a Cloud SQL
instance first exists. Until then this row is a definition, not a result, and
should not be relied on.

### 3. Expensive unused services — DOES NOT WORK AS BUILT

`constraints/gcp.restrictServiceUsage` with a denied list of
vmwareengine, baremetalsolution, datafusion, composer, bigtable and
gkemulticloud.

**It did not refuse.** A Bigtable instance (~$0.65/hr/node) was created twice
while `bigtable.googleapis.com` was in the denied list — once four minutes
after the policy was applied and again at ten minutes, by which point the VM
constraint was already enforcing. Both were deleted immediately.

Bigtable **is** on Google's supported-services list for this constraint, so
this is not an unsupported-service case. The policy is stored correctly:

    deniedValues:
    - vmwareengine.googleapis.com
    - baremetalsolution.googleapis.com
    - datafusion.googleapis.com
    - composer.googleapis.com
    - bigtable.googleapis.com
    - gkemulticloud.googleapis.com

The documentation describes the constraint as controlling "runtime access to
all in-scope resources", which appears not to include the admin call that
creates an instance. **Treat this guardrail as absent until it has been seen to
refuse something.** The likely replacement is restricting which APIs may be
ENABLED at all, so the service never becomes available to call; that is a
different constraint and has not yet been built or tested.

## What none of this protects against

A unit-price cap is a narrow instrument. It does not stop:

- **Quantity.** Nothing limits how MANY e2-micros exist. Fifty allowed VMs cost
  more than one forbidden one. There is no count limit anywhere in this lab.
- **Time.** A guardrail refuses creation; it has no opinion about a small thing
  left running for a month. Week 13's $1.99 was eleven hours of allowed
  resources. Left up, the same deployment is about $146/month.
- **Per-use and per-GB services.** BigQuery query cost, Cloud Storage egress,
  Pub/Sub volume, log ingestion — none has a "size" to cap. A single bad
  BigQuery query can cost more than every VM this lab has ever created.
- **Anything not on the deny list.** The service list names six. Google has
  hundreds, and new expensive ones appear.
- **Resources a destroy leaves behind.** Week 12's KMS key version survived a
  successful `terraform destroy`. `scripts/check_nothing_running.py` is the
  answer to that, and it is a detector, not a preventer.
- **The budget being an alert.** Still true. Nothing stops spend at $25.

The honest summary: these guardrails make one specific accident — reaching for
a big machine out of habit — impossible. They do nothing about the accident
that has actually cost this lab money, which is leaving something running.

## Pricing data: the reservation trap

Checked 2026-11-22 after the Azure lab reported $1,883/hour for a database that
costs $0.18/hour, because its price API returned 3-year reservation totals
against a "1 Hour" unit.

The GCP pricing export carries the same hazard class. Of its rows:

| Kind | Rows |
| --- | --- |
| on-demand / other | 5,115,664 |
| commitment (1yr/3yr prepay) | 562,752 |
| reservation | 77,440 |

**7,932 commitment or reservation SKUs are priced in `HOUR`**, and 591 in
`MONTH` with a maximum unit price of **$200,000**. A query that matches a
resource by name and takes an hourly row can land on one.

GCP is less treacherous than Azure here — its hourly commitment figures are
effective hourly rates rather than a multi-year total — but any estimator built
against this table must filter commitment and reservation SKUs and assert the
pricing unit it expects. There is no such estimator in this lab yet; when one
is written, that filter is a requirement, not a refinement.

The only price script that exists today, `fetch_aws_prices.py` in the blog
repo, reads `doc["terms"]["OnDemand"]` explicitly and never touches
`terms["Reserved"]`. It is not affected.

## Reproducing the proof

    bash scripts/prove_guardrails.sh

It attempts a forbidden machine type and expects a denial, attempts an allowed
one and expects success, and deletes anything it manages to create. A guardrail
nobody has watched refuse something is not a guardrail, and the only way to
keep knowing it works is to run this again.

**Org policy is not instant.** The machine-type constraint was created at
17:13:30Z and still allowed an n2-standard-8 at 17:14; it refused at 17:17:45Z.
Roughly four minutes. A proof run immediately after an apply will produce a
false negative, which is how this one nearly got written up as working when it
was not.

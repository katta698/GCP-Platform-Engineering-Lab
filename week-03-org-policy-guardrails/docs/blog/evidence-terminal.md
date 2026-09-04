# Terminal evidence — Week 03

Output that exists nowhere else. Everything a run produced is preserved in the
HCP run log and can be screenshotted later; what is recorded here is the output
that never reached HCP, because it was rejected by the CLI before a run was
created. It is not recoverable by re-running once the configuration is fixed.

All captured 2026-09-03 against the live organization. Identifiers redacted.

---

## 1. Writing organization policy requires an API that reading it does not

First apply attempt. `terraform plan` had succeeded moments earlier and reported
`7 to add, 0 to change, 0 to destroy`.

```
Error 403: Organization Policy API has not been used in project <PROJECT_NUMBER>
before or it is disabled.

  "reason": "SERVICE_DISABLED",
  "service": "orgpolicy.googleapis.com",
  "consumer": "projects/<PROJECT_NUMBER>"

  with google_org_policy_policy.org["compute.managed.disableSerialPortAccess"]
```

Worth stating precisely, because the obvious reading is wrong. Organization
policy is not stored in a project, so it is natural to assume no project needs
anything enabled. The *write* goes through the caller's quota project, and that
project must have `orgpolicy.googleapis.com` on. The *read* does not — the seven
baseline constraints had already been listed successfully, and the plan refreshed
without complaint.

So a clean plan is not evidence that an apply will work. The dependency does not
exist until the first write.

---

## 2. The Organization Policy API serializes changes per parent

Second apply attempt, after adding `google_project_service.orgpolicy`.

```
Error: Error creating Policy: googleapi: Error 409: Creating policy failed.
Please retry the request.

  "reason": "CONCURRENT_POLICY_CHANGES",
  "domain": "orgpolicy.googleapis.com"

  with google_org_policy_policy.org["compute.managed.blockProjectSshKeys"]
```

Terraform's default parallelism is 10. The four boolean policies shared one
parent — the organization — and the API rejected the overlapping writes.

The failure is **partial and non-deterministic**, which is the part that makes it
awkward rather than merely annoying. `terraform state list` after this run showed
two of the four policies created:

```
google_org_policy_custom_constraint.bucket_labels
google_org_policy_policy.bucket_labels
google_org_policy_policy.org["compute.managed.requireOsLogin"]
google_org_policy_policy.org["iam.managed.disableServiceAccountApiKeyCreation"]
google_project_service.orgpolicy
```

Re-running would converge eventually. Converging by repetition is not a
deployment.

---

## 3. The CLI workaround does not exist on remote execution

The documented answer to a concurrency limit is to lower Terraform's parallelism.
On this workspace that is refused, and refused locally — no run was created, so
this output appears in no HCP run log:

```
$ terraform apply -auto-approve -input=false -parallelism=1

Error: Custom parallelism values are currently not supported

HCP Terraform does not support setting a custom parallelism value at this
time.
```

This is the finding the week turns on, and it is a consequence of Week 03 being
the first week to run remotely rather than anything about organization policy.

On local execution the fix is a flag. A flag leaves the configuration wrong and
moves the correction into an operator's memory — it works for exactly as long as
the person who learned it is the person running it.

On remote execution there is no flag to reach for, so the ordering has to be
expressed as an edge in the dependency graph. That is a property of the code. It
survives being run by someone who was never told.

The constraint forced the better fix.

---

## 4. What a dry-run violation actually looks like

The measurement the whole method rests on. A bucket was created in the seed
project with no labels, while `custom.requireTerraformLabelsOnBuckets` was set as
a dry-run policy. The request **succeeded** — dry run denies nothing — and this
is the audit record it produced:

```json
"metadata": {
  "@type": "type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata",
  "constraint": "customConstraints/custom.requireTerraformLabelsOnBuckets",
  "dryRunResult": "DENIED",
  "liveResult": "ALLOWED",
  "resourceType": "storage.googleapis.com/Bucket"
},
"status": {
  "code": 7,
  "message": "POLICY_VIOLATED"
}
```

`dryRunResult: DENIED` beside `liveResult: ALLOWED` is the entire value of dry
run in two fields: what the rule would have done, and what actually happened.
Enforcing this constraint is now an informed decision rather than a hopeful one.

Two details that are easy to get wrong and are worth stating precisely.

**The status says `POLICY_VIOLATED` with gRPC code 7 (PERMISSION_DENIED) on a
request that succeeded.** The bucket exists. Anything that alerts on
`status.code != 0` — or greps audit logs for `POLICY_VIOLATED` — will treat every
dry-run evaluation as a live denial and report an outage that is not happening.
That is a plausible way to lose confidence in a monitoring stack during exactly
the week it is most needed.

**The entry is in the PROJECT's audit log, not an organization-level policy
stream.** The policy is set at the organization; the log is written where the
request was served. Reading the organization for
`logName:"cloudaudit.googleapis.com%2Fpolicy"` returns nothing, and returns it
without an error, which looks identical to "no violations occurred". The only
organization-level stream present on this org is
`cloudaudit.googleapis.com%2Factivity`.

The query that works:

```bash
gcloud logging read \
  'protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.OrgPolicyDryRunAuditMetadata"' \
  --project="$SEED_PROJECT" --freshness=2h
```

The probe bucket was deleted immediately after the record was read.

---

## 5. The denial, and the same request allowed

`custom.requireTerraformLabelsOnBuckets` promoted from dry run to enforced on
2026-09-03, after its dry-run violation had been read. Both requests made as
`katta698@jayanthkatta.com`, which holds permission to create the bucket — an
attempt by an under-privileged identity fails with a permission error that looks
identical to the constraint working and proves nothing.

**Without labels — refused:**

```
$ gcloud storage buckets create gs://wk03-denytest-... --uniform-bucket-level-access
ERROR: HTTPError 412: orgpolicy:projects/_/buckets/wk03-denytest-... violates
customConstraints/custom.requireTerraformLabelsOnBuckets.
Details: Storage buckets must carry the three labels this lab requires of every
resource. managed-by must be terraform, so a bucket created by hand in the
console is refused.

- '@type': type.googleapis.com/google.rpc.PreconditionFailure
```

HTTP **412 Precondition Failed**, not 403. The constraint is named, and the
`description` field written in Terraform is quoted back to the caller — which is
the argument for writing that field for the person who will hit the wall rather
than as a change-log entry.

**With the three labels — created:**

```
POST https://storage.googleapis.com/storage/v1/b?project=...
{"name":"...","labels":{"week":"03","env":"dev","managed-by":"terraform"}}

HTTP 200
labels: {'env': 'dev', 'managed-by': 'terraform', 'week': '03'}
```

The allow half had to go through the JSON API: **`gcloud storage buckets create`
has no label flag at all**, so the rule cannot be satisfied by the command most
people would reach for. A constraint that can only be complied with by a
different tool than the one that trips it is worth knowing about before it is
enforced organization-wide.

## 6. Enforcement is not instant

The first denial attempt **succeeded** — the bucket was created roughly a minute
after the flip to enforced, while `describe --effective` already reported
`enforce: true`. The same request was refused about two minutes later.

So the effective policy is readable before it is enforced, and the two are not
the same thing. A validation script that tests immediately after an apply will
report a working constraint as broken, and the natural conclusion — that the
constraint is wrong — sends you editing correct code.

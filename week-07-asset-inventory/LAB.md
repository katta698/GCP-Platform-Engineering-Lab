# Lab Guide — Week 07: Resource Hierarchy Audit with Cloud Asset Inventory

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-07-asset-inventory/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-09-29. Still running — the feed and
snapshot cost nothing and later weeks read them.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with several projects, ideally some outside a folder, so the audit has something to find |
| Apply identity | `roles/cloudasset.owner` at the organization (see §7 — this is a real over-grant, narrowed in Week 08) |
| Operator | `roles/cloudasset.viewer` at the organization, for the snapshot script |
| APIs | `cloudasset.googleapis.com`, `pubsub.googleapis.com`, `bigquery.googleapis.com` on the quota project |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

**Cross-week:** Week 1 supplies the hierarchy being audited. Nothing else is
required.

**Region:** the BigQuery dataset is regional; everything else is global.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization being inventoried — **sensitive** |
| `seed_project_id` | hosts the feed, topic and dataset |
| `region` | BigQuery dataset location |

---

## 3. Deploy

```bash
cd week-07-asset-inventory/terraform
terraform init
terraform plan      # expect: 7 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`

| Resource | Purpose |
| --- | --- |
| `google_cloud_asset_organization_feed` | streams asset changes to Pub/Sub |
| `google_pubsub_topic` | the feed's destination |
| `google_bigquery_dataset` | holds snapshot exports |
| 3 × IAM bindings | grants to the **Cloud Asset service agent**, see below |
| `google_project_service` | API enablement |

### The grant that is not obvious

**Cloud Asset Inventory writes to destinations as itself, not as the caller.**
Being project owner on the destination is not enough and never becomes enough.
Three grants go to
`service-<PROJECT_NUMBER>@gcp-sa-cloudasset.iam.gserviceaccount.com`:

| Role | On |
| --- | --- |
| `roles/pubsub.publisher` | the topic |
| `roles/bigquery.dataEditor` | the dataset |
| `roles/bigquery.jobUser` | the project |

Expect this shape for any Google service that delivers somewhere on your behalf.

### The snapshot is not a Terraform resource

An export is an operation with a moment attached, not a desired state. It lives
in `scripts/snapshot.sh`:

```bash
./scripts/snapshot.sh
```

---

## 4. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-09-29 |
| --- | --- | --- |
| Feed exists and targets the topic | feed resolves, topic matches | both correct |
| Cloud Asset Inventory can publish | service agent holds `pubsub.publisher` | present |
| Snapshot has recent rows | row count > 0, dated today | rows present |
| Projects not in a folder | reported | **2 of 7** |
| User-managed service account keys | zero | **zero** — see below |

### Two audit findings worth reproducing

**Two of seven projects sit directly under the organization**, not in a folder.
Week 5's `custom.requireProjectNamingAndParent` constraint is still **dry run**,
so it denies nothing — and both projects predate it, so promoting it would not
retroactively fix either.

**The naive key query says two keys; the real answer is zero.** Both are
`SYSTEM_MANAGED` / `GOOGLE_PROVIDED`. Always filter on `keyType`:

```sql
SELECT name FROM `<dataset>.<table>`
WHERE asset_type = 'iam.googleapis.com/ServiceAccountKey'
  AND JSON_VALUE(resource.data, '$.keyType') = 'USER_MANAGED'
```

---

## 5. Cleanup

```bash
terraform destroy
```

**Verify:** the feed should no longer appear in
`gcloud asset feeds list --organization=<ORG_ID>`, and the dataset and topic
should be gone.

**Cost:** $0. Feeds and exports are free; the snapshot is a few kilobytes of
BigQuery storage.

**Preserve if later weeks need it:** Week 08 narrows the plan identity's access
to this feed, so destroying Week 07 removes what Week 08 is about.

---

## 6. Troubleshooting

### `The caller does not have permission` on the BigQuery export

**Cause.** The Cloud Asset service agent, not the caller, needs
`bigquery.dataEditor` on the dataset and `bigquery.jobUser` on the project.

**Fix.** Grant to `service-<PROJECT_NUMBER>@gcp-sa-cloudasset.iam.gserviceaccount.com`.

**Note on error quality.** The same missing grant on Pub/Sub produces an
excellent error naming the service account, the permission and the resource. On
BigQuery it produces four words. Same service, same class of mistake, wildly
different diagnosability.

### The Asset Inventory dashboard shows stale data

**Cause.** The console dashboard is cached. It reported "last updated September
23" beside an export minutes old.

**Fix.** Query the snapshot table, not the page.

### No read-only role can read an asset feed

**Cause.** `roles/cloudasset.viewer` lacks `cloudasset.feeds.get`. Only
`roles/cloudasset.owner` has it, and that also grants create, update and delete.

**Fix in this lab:** none — the plan identity was given owner, and the lab's
read-only-plan guarantee has a documented hole. **Week 08 closes it** with a
custom role and a deny policy.

---

## 7. Known limitations

- **The plan identity holds `roles/cloudasset.owner`.** That is a genuine
  over-grant, accepted here because no narrower role can read a feed, and
  remediated in Week 08. Do not leave it in place.
- **The snapshot is a point in time**, taken by hand. Drift detection would
  need it on a schedule with diffs between runs.
- **The audit reports; it does not enforce.** Two projects outside a folder were
  found and left, because the constraint that would prevent it is in dry run and
  is not retroactive.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Scheduling | Snapshot on a schedule and diff consecutive exports, rather than exporting on demand |
| Enforcement | Promote the naming/parent constraint out of dry run, accepting that existing violations need separate remediation |
| Access | Narrow the reader to a custom role (Week 08) instead of `cloudasset.owner` |
| Alerting | Act on the feed, not only the snapshot — the feed is the real-time half and this lab only stores it |

---

## 9. References

- [Cloud Asset Inventory overview](https://docs.cloud.google.com/asset-inventory/docs/overview)
- [Monitoring asset changes with feeds](https://docs.cloud.google.com/asset-inventory/docs/monitoring-asset-changes)
- [Exporting to BigQuery](https://docs.cloud.google.com/asset-inventory/docs/exporting-to-bigquery)
- [Terraform `google_cloud_asset_organization_feed`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_asset_organization_feed)

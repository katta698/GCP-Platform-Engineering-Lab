# Week 07 — Resource hierarchy audit and drift

Status: ✅ **Deployed 2026-09-29.**

## Cost note

**$0.** Cloud Asset Inventory exports and feeds are free. The snapshot is a few
hundred rows of BigQuery storage, far below the 10 GiB free tier, and the topic
has no subscriber so nothing accumulates.

This week is **exempt from teardown** — the feed only has value while it is
running, and the snapshot is the thing later weeks compare against.

## What this week builds

```
organization
├── feed  hierarchy-changes  ──►  Pub/Sub  asset-hierarchy-changes   what CHANGED
│         Project + Folder only                (logging project)
└── gcloud asset export      ──►  BigQuery asset_inventory.hierarchy what IS
                                              (logging project)
```

Two shapes of the same data. The feed is a Terraform resource; the export is
not — there is no `google_cloud_asset_*` resource for it, because a snapshot is
an operation with a moment attached rather than a thing you own. It lives in
`scripts/snapshot.sh`.

## What the audit found

The point of an inventory is to answer a question you cannot answer by
remembering. Two answers, in one query each.

**Two of seven projects sit directly under the organization**, not in a folder:

```
project_id                 state             depth  parent
dev-adapter-506301-k1      ACTIVE                2  organizations/…
katta698-gcp-lab-seed      ACTIVE                2  organizations/…
katta698-gcp-dev-app-01    DELETE_REQUESTED      4  folders/…
katta698-gcp-dev-app-02    ACTIVE                4  folders/…
katta698-gcp-logging       ACTIVE                3  folders/…
katta698-gcp-net-hub       ACTIVE                3  folders/…
katta698-gcp-security      ACTIVE                3  folders/…
```

Week 05 wrote a custom constraint requiring exactly the opposite — a project ID
starting with the org prefix, and a parent that is a folder. It is still in
**dry run**, so it denies nothing, and both of these predate it. `dev-adapter-506301-k1`
breaks the naming half too, and I had forgotten it existed.

That is the honest shape of a creation-time rule: it governs what comes next and
says nothing about what is already there. The inventory is how you find out
which is which.

**Zero user-managed service account keys** — but the naive query says two:

```
service_account         key_type        key_origin
…719141                 SYSTEM_MANAGED  GOOGLE_PROVIDED
…820355                 SYSTEM_MANAGED  GOOGLE_PROVIDED
```

Both are Google's own rotating signing keys, not downloadable credentials. The
lab's "no service account keys, ever" rule holds. Worth stating because
`COUNT(*) WHERE asset_type = ServiceAccountKey` returns 2 and looks alarming.

## Measured findings

**Cloud Asset Inventory writes as itself, never as the caller.** Being project
owner on the destination is not enough and never becomes enough. Three grants
are needed and all three are to the *service agent*: `pubsub.publisher` on the
topic, `bigquery.dataEditor` on the dataset, `bigquery.jobUser` on the project.

**The feed's error is excellent. The export's is four words.** Creating a feed
without the publisher binding names the service account, the permission and the
resource. The same missing-grant condition on the BigQuery destination gives
`The caller does not have permission` and nothing else — same product, same
release, opposite quality.

**No read-only role can read an asset feed.** `roles/cloudasset.viewer` does not
carry `cloudasset.feeds.get`; only `roles/cloudasset.owner` does, and it also
grants create, update and delete. Since every HCP apply runs a plan first as
`tf-plan`, the plan identity had to be given owner. The read-only guarantee this
lab maintains everywhere else does not hold for this one resource, and that is
written down in `week-02-keyless-ci` rather than discovered later.

**The console dashboard is not live.** It reported "last updated September 23"
while the export was minutes old, and its counts differ accordingly. For a
question that matters, query the snapshot.

**A human cannot borrow the CI identity.** `tf-apply` is impersonatable only by
the HCP workload identity principal set, so the operator running `snapshot.sh`
needed their own `roles/cloudasset.viewer` grant. That is the keyless design
working as intended, and it costs one grant.

## Order of work

1. `terraform apply` — remote, as `tf-apply`
2. Grant what CI cannot do, in **`week-02-keyless-ci`**, hand-applied
3. `ORG_ID=... ./scripts/snapshot.sh`
4. `ORG_ID=... ./scripts/validate.sh`

## Evidence

- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/references.md` — what each source settled, and what none of them did

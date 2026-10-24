# Week 10 — Group-based access

**Goal:** make a role in this organization be held by a *group* instead of a
person, and prove that access appears and disappears with group membership and
nothing else.

**Blog post:** https://jayanthkatta.com/blog/week-10-group-access/
(published 2026-10-24)

## Cost note

**$0.** Cloud Identity Free covers groups and memberships; nothing compute,
storage or network was created. **Torn down 2026-10-24** — all 6 resources
destroyed and verified against the cloud, not against state.

Two things survive the teardown and cost nothing but are not nothing:

- `tf-apply` holds the **Groups Admin** Workspace admin role
- `tf-plan` holds a **custom Workspace role carrying only Groups → Read**

Neither is Terraform-managed, so `terraform destroy` does not remove them, and
there is now no group for them to administer. **Revoke them in the Admin console**
(Account → Admin roles) — see Cleanup below.

## What existed, before it was destroyed

```
customers/<directory>
└── grp-gcp-log-readers@jayanthkatta.com      access group, 1 member
    └── group-access-demo@<seed>              service account holding NO direct role

folders/platform
└── roles/logging.viewer  ->  group:grp-gcp-log-readers@...
    inherited by katta698-gcp-logging and every other project in the folder
```

6 resources in workspace `gcp-week-10`. Four of them exist only so the test
means something: the subject had to be an identity whose *only* route to the
permission was the membership.

## Measured findings

**Access follows membership in 10–30 seconds, both directions.** Three trials
each way, ten-second poll, measured against the deployed group with
`scripts/measure-membership-lag.sh`. Six transitions, none of which edited an
IAM policy.

Google documents a propagation delay for membership arriving from an **external
identity provider** and puts it at up to several hours. There is no external
provider here, so that figure describes a different system and must not be
quoted for this one.

**`initial_group_config = "WITH_INITIAL_OWNER"` conferred no ownership.** The
group was created with **zero members and no owner**, confirmed through both
gcloud and the REST API. Google's documentation offers this as the
least-privilege path for a pipeline — "consider making it an owner of the groups
of interest" — and the Terraform provider accepts the setting, and the result was
a group its creator could not read, update or add members to. An apply that
reports success and leaves an unmanageable object is worse than a refused
request.

**Workspace admin role grants take minutes to take effect**, and during that
window the Cloud Identity API returns a flat `403 Permission denied` that is
indistinguishable from a wrong permission. An identical apply five minutes later
succeeded with nothing changed. Observed once — an anecdote, not a range — but
enough to know that waiting belongs before redesigning.

**Refresh runs as the PLAN identity.** Granting the apply identity Groups Admin
changed nothing, because `Refreshing state...` for the group happens in the plan
phase. A read-only CI identity needs its own directory authorization, and Cloud
Identity publishes no read-only service-account path — only Group Administrator.
Week 02's plan/apply split is a real security property and it collides here.

**`gcloud identity groups search --organization=<ORG_ID>` returns zero, always.**
Groups are parented to `customers/<id>`, not to the organization, so the query
names a parent no group can have. It exits 0 and prints nothing, which reads
exactly like "there are no groups" — and it is what this week's premise was
checked with. The premise held, but only the Admin console screenshot ever
proved it. Use the REST `groups:search` with `parent=='customers/<id>'`, or
`gcloud identity groups describe` by address.

**Cloud Identity is a client-based API.** It bills the caller's project, and the
resource has no project at all. `--billing-project` is required on the CLI;
`user_project_override = true` is required on the provider. Without it the call
is attributed to a Google-owned project and fails `SERVICE_DISABLED` naming a
project number that appears nowhere in this lab.

## Verify

```bash
ORG_ID=<org> ./scripts/validate.sh              # ran green end to end 2026-10-24
ORG_ID=<org> ./scripts/measure-membership-lag.sh 3
```

`validate.sh` asserts against the live organization rather than Terraform state:
the group exists, the subject holds **nothing** directly, it is a `MEMBER` and
not a manager, the folder role is held by a **group**, and the subject can read
logs right now. It was run before the teardown, which matters — after a destroy
it can never be run again.

## Cleanup

```bash
terraform destroy          # done 2026-10-24: 6 destroyed
```

Then, **by hand in the Admin console**, because the directory is a separate
system and Terraform does not reach it:

- Account → Admin roles → **Groups Admin** → remove `tf-apply@…`
- Account → Admin roles → **Terraform plan - groups read only** → remove
  `tf-plan@…`, then delete the role

## References

See `docs/references.md`, including what the documentation did **not** settle.

# Week 08 — Least privilege, and the guardrail that keeps it

Status: ✅ **Deployed 2026-10-05.**

## Cost note

**$0.** Custom roles, deny policies and Policy Troubleshooter are all free. No
project was created; nothing here runs.

The real cost is **maintenance**: a custom role does not track Google. When a
predefined role gains a permission, this one does not, and a plan fails until
someone adds it. That is the honest price of least privilege and it is why
predefined roles still exist.

## The problem this fixes

Week 07 left a hole and wrote it down. `tf-plan` — the identity HCP assumes
during `terraform plan`, which is supposed to be read-only — was given
`roles/cloudasset.owner`, because no predefined role carries
`cloudasset.feeds.get` without also carrying create, update and **delete**.

```
BEFORE   tf-plan / cloudasset.feeds.delete  ->  GRANTED
```

A read-only identity that can delete things is not read-only.

## What this week builds

**The fix — a custom role.** `tfPlanAssetReader`, two permissions,
`cloudasset.feeds.get` and `.list`. `tf-plan` is moved onto it and
`roles/cloudasset.owner` is removed.

**The guardrail — a deny policy.** `deny-asset-feed-deletion` refuses
`cloudasset.googleapis.com/feeds.delete` to **all principals**, with two
exceptions:

| exception | why |
| --- | --- |
| `tf-apply` | Terraform legitimately manages the feed's lifecycle |
| a break-glass human | a deny with no way out gets deleted under pressure, which removes the control entirely instead of using it once |

The order matters. The custom role is the fix; the deny policy is what survives
someone re-granting a broad role next quarter. Shipping only the guardrail would
leave an identity holding owner and call it safe.

## Proving it, rather than claiming it

```
AFTER    tf-plan  / feeds.delete   ->  CANNOT_ACCESS
         tf-plan  / feeds.get      ->  CAN_ACCESS      (still works)
         tf-apply / feeds.delete   ->  CAN_ACCESS      (exempted)
```

`CANNOT_ACCESS` there is the custom role doing the work — the permission is not
granted at all, so the request never reaches the deny policy. **That means the
guardrail was untested**, so it was tested directly: `roles/cloudasset.owner`
was re-granted to `tf-plan` to simulate the future mistake, and

```
allow policies say:  ALLOW_ACCESS_STATE_GRANTED
deny policies say:   DENY_ACCESS_STATE_DENIED
overall:             CANNOT_ACCESS
matched policy:      deny-asset-feed-deletion
```

Deny beats allow. The over-grant was then removed.

## Measured findings

**Policy Troubleshooter v1 cannot see deny policies.** With the deny actively
blocking, v1 answered `GRANTED` and v3 answered `CANNOT_ACCESS` — same question,
same moment. `gcloud policy-troubleshoot iam` calls **v1**. Anything that checks
a deny policy must call v3 explicitly, or it will pass while the control does
nothing.

**Deny policies use different principal identifiers to everything else.** Not
the `serviceAccount:` member string Terraform uses everywhere:

```
service account   principal://iam.googleapis.com/projects/-/serviceAccounts/<email>
human             principal://goog/subject/<email>
everyone          principalSet://goog/public:all
```

The allow-policy spelling fails with `invalid principal ... as part of the
exempted principals list`.

**Creating a custom role requires permission to read one.** The failure was not
"cannot create" but *"Unable to verify whether custom org role ... already
exists and must be undeleted"* — deleted custom roles linger for 7 days and can
be undeleted, so the provider reads before it writes.

**The deny/reviewer role split is clean, unlike Week 07's.** `roles/iam.denyAdmin`
has `denypolicies.create`; `roles/iam.denyReviewer` has only `get`. So the
read-only plan identity gets a genuinely read-only role here — which is the
counter-example proving Week 07's gap was a flaw in *that* service's role
design, not a rule about GCP.

**The operator needed read grants again.** Troubleshooter returned
`UNKNOWN_INFO_DENIED` — not a denial, an inability to explain — until the human
account held `roles/iam.organizationRoleViewer` and `roles/iam.denyReviewer`.
Second week running that the person running the validator needed their own
read-only grants.

## Rollback

Written before the apply, not after:

```bash
# 1. remove the guardrail  (as a principal holding roles/iam.denyAdmin)
gcloud iam policies delete deny-asset-feed-deletion \
  --attachment-point="cloudresourcemanager.googleapis.com/organizations/$ORG_ID" \
  --kind=denypolicies

# 2. put the broad role back, if a plan is genuinely broken
#    in week-02-keyless-ci, swap plan_asset_reader back to roles/cloudasset.owner
```

The break-glass exception exists so step 1 is rarely needed: one named human can
perform the denied action without removing the control for everyone.

## Order of work

1. Measure the before state with Troubleshooter **v3**
2. `terraform apply` here — the custom role and the deny policy
3. Grant what CI cannot do, in **`week-02-keyless-ci`**, hand-applied
4. Swap `tf-plan` onto the custom role, same file, same way
5. `ORG_ID=... ./scripts/validate.sh`

## Evidence

- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/references.md` — what each source settled, and what none of them did

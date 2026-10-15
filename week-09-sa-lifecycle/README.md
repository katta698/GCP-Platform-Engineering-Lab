# Week 09 — Service account hygiene

Status: ✅ **Deployed 2026-10-14.**

## Cost note

**$0.** Disabling an identity costs nothing and nothing here runs. The
organization's measured lifetime spend is still **$0.006 since 1 July**, read
from the billing export rather than a rate card.

**Exempt from teardown**, with a caveat: the Terraform sets
`restore_policy = "REVERT"`, so destroying this week deliberately **re-enables**
the accounts rather than leaving them disabled with nothing managing them.

## The question this week asks

Week 02 built the mechanism — who may become whom, keylessly, with short-lived
tokens. This week asks a different question about the same objects: **which of
these identities should still exist at all.**

Measured before writing any code, with Activity Analyzer:

```
finops-reader@…        last authenticated 2026-10-09
tf-plan@…              last authenticated 2026-10-05
tf-apply@…             last authenticated 2026-10-05
398884169348-compute@  NEVER AUTHENTICATED
851623897121-compute@  NEVER AUTHENTICATED
```

The last two are default Compute Engine service accounts, in the logging and
security projects. Nobody created them, nobody has ever used them, and they hold
no role anywhere.

`finops-reader` was nearly assumed unused and is not — it authenticated five days
ago. That is the argument for measuring rather than reasoning about which
identities look idle.

## What this week builds

| Resource | Count | Job |
| --- | --- | --- |
| `google_project_default_service_accounts` | 2 | disable the unused default SAs |
| `google_org_policy_policy` | 1 | enforce key creation off on the **legacy** constraint |

## Disable, never delete

Google's guidance is to disable first and delete only once you are sure. The
reason is sharper than "it is reversible":

**A deleted service account's email can be reused, but IAM tracks an internal
unique ID.** Role bindings that referred to the deleted account never apply to a
replacement created with the same address. A rebuild looks identical and is not.

`DISABLE` is one field, reversible, and visible in the console.

## The trap, and the week's main finding

This lab's first rule is "no service account keys, ever", and Week 02 published
that the organization enforces it. While planning this week I checked:

```
iam.disableServiceAccountKeyCreation            enforce=False
```

and briefly concluded the rule was not enforced at all. It is — on the **managed**
constraint generation:

```
iam.managed.disableServiceAccountKeyCreation    enforce=True
```

Google's own security baseline is mid-migration and uses *different generations*
for the two key constraints — something Week 03 documented and I failed to recall
before alarming myself. The legacy constraint simply had no policy, and a
constraint with no policy reads `enforce: false`.

So this week sets the legacy one too. It is redundant while the baseline holds,
which is what defence in depth means, and it removes the trap for whoever checks
next.

## Proving it was safe

Disabling an identity is only safe if nothing depended on it. The proof is that
every previous week still passes:

```
All Week 06 checks passed.
All Week 07 checks passed.
All Week 08 checks passed.
```

## Order of work

1. Measure last authentication for every service account — **before** anything
2. Capture the console "before" view, which cannot be recreated after the apply
3. `terraform apply` — remote, as `tf-apply`
4. `ORG_ID=... ./scripts/validate.sh`
5. Re-run Weeks 06–08 validators to prove nothing broke

No new grants were needed in `week-02-keyless-ci` this week — `tf-apply` already
held what it needed.

## Evidence

- `docs/FIGURE_PLAN.md` — the four slots, declared before capturing
- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/references.md` — what each source settled

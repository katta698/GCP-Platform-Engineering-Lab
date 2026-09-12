# Week 04 — Shared VPC hub-and-spoke

Status: ✅ **Deployed 2026-09-12.** First week in this lab that anything runs.

## Cost note

**~$0, and the shape is deliberate.** Four choices keep it inside Always Free,
and changing any one of them silently turns a free week into a billed one:

| choice | why |
| --- | --- |
| `e2-micro` | the only machine type in the free tier |
| `us-central1` | free tier covers `us-west1`, `us-central1`, `us-east1` only |
| `pd-standard`, 10 GB | the free 30 GB-month allowance is **standard** disk; `pd-balanced` is the default and bills from the first byte |
| **no external IP** | an external IPv4 address bills per hour whether traffic flows or not, and is not in the free tier |

Shared VPC, subnets, firewall policies and the extra project are all free.
`validate.sh` asserts the external IP is absent, which is a **cost** check rather
than a connectivity one — an accidental external address is a bill that appears
without anything appearing broken.

## Why this week moved from 12 to 04

Not for variety. Week 03 left three constraints in dry run —
`requireOsLogin`, `blockProjectSshKeys`, `disableSerialPortAccess`. A dry-run
policy logs when it *would have denied a request*, and with no Compute Engine
resource anywhere in the organization there were no requests to evaluate. Those
three could never be promoted on evidence. The original ordering parked Week 03's
own unfinished business nine weeks out.

## What was deployed

```
katta698-gcp-net-hub  (platform folder)        HOST
└── hub                       custom-mode VPC
    ├── dev-us-central1       10.20.0.0/24     flow logs, Private Google Access
    └── prod-us-central1      10.20.1.0/24     reserved, attached to nothing

workloads/                    hierarchical firewall policy "workloads-baseline"
│                             1000  allow  INGRESS  35.235.240.0/20 tcp:22  (IAP)
│                             65000 deny   INGRESS  0.0.0.0/0 all
└── dev/
    └── katta698-gcp-dev-app-01  (SERVICE)
        └── dev-app-01           e2-micro, 10.20.0.2, no external IP
```

The instance is in the service project. Its address comes from a subnet in the
**host** project. That is the whole of Shared VPC in one value.

## Measured findings

**The CI identity could not do this week, and that is correct.** `tf-apply` held
six roles covering folders, projects, service usage, service accounts and org
policy — and not one compute permission. The fix could not go in this week's
configuration: Week 02 established that **an identity must not manage its own
grants**, so a config applied by `tf-apply` that also widens `tf-apply` lets CI
give itself anything. The grants went into the human-run layer instead. Widening
CI became a separate, reviewable act.

**Creating a firewall policy and attaching it are different roles**, and the
names do not say so:

```
roles/compute.orgSecurityPolicyAdmin     firewallPolicies.create/update/use
                                         NOT organizations.setFirewallPolicy
roles/compute.orgSecurityResourceAdmin   organizations.setFirewallPolicy
```

So the policy created cleanly and the association was refused. Reasonable once
stated — a policy attached to nothing is inert, so attachment is the act that
changes behaviour — but the error names a permission without naming a role that
grants it.

**A folder-scoped firewall policy needs a quota project.** It is owned by no
project, and the Compute API is client-based, so with none set it fails:

```
Error 404: The resource 'projects/null' was not found
```

which reads like a missing resource rather than a missing header. The bootstrap
hit the identical thing on the Budgets API in August.

**And setting `user_project_override` cascades.** Every call is then attributed
to the host project, so it needed `cloudresourcemanager`, `serviceusage` and
`cloudbilling` APIs enabled — services it does not itself use. Enabling them is
chicken-and-egg: the enabling call is also attributed there, so the first one had
to be done by hand.

**A billing account caps how many projects it will fund.** Project creation
failed with `Cloud billing quota exceeded` at five linked projects. Freeing a
slot needed the *owning* identity — the org admin could not unlink a project that
sits outside the organization.

**Enforcement lag is a property of the policy system, not of one constraint.**
Week 03 measured 75–100s on a custom constraint. The first attempt to violate
`blockProjectSshKeys` **succeeded** ~1–2 minutes after promotion; the same
request minutes later was refused. Same phenomenon, different constraint
generation.

**Enforcement is not retroactive**, and Google says so in the denial itself:

> Enforcing this constraint does not affect existing VMs where
> `block-project-ssh-keys` is already set to false; they will retain access
> unless their metadata is updated.

A VM weakened before the constraint went on stays weakened. This is the same
property that put governance before workloads in this roadmap.

**The Week 03 exception, finally demonstrable.** Asserted since 2026-09-03 from
`gcloud` output; now evaluated by Google's own policy engine at three scopes:

```
constraint                                 org    dev    prod
compute.managed.requireOsLogin             True   True   True
compute.managed.blockProjectSshKeys        True   True   True
compute.managed.disableSerialPortAccess    True   False  True
```

One row, one column. Inheritance everywhere else, override exactly where it was
written.

## Order of work

1. `ORG_ID=... ./scripts/read-current-policy.sh` from Week 03 — with `--effective`
2. Grant the compute roles in **`week-02-keyless-ci`**, hand-applied
3. `terraform apply` here — remote, as `tf-apply`
4. Promote Week 03's three constraints now that there is something to evaluate
5. Wait for enforcement to take effect — it is **not** immediate
6. `ORG_ID=... HOST_PROJECT=... SERVICE_PROJECT=... ./scripts/validate.sh`

## Evidence

- `docs/blog/screenshots/` — console captures, identifiers redacted
- `docs/references.md` — what each source settled, and what none of them did

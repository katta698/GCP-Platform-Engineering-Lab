# Lab Guide — Week 04: Shared VPC Hub and Spoke

**How to reproduce this lab.** The [blog post](https://jayanthkatta.com/blog/week-04-shared-vpc/)
explains what it does and why; this guide is the runbook.

**Status:** deployed and validated 2026-09-12. **The spoke was destroyed in
Week 05** to free a billing slot; the hub VPC, both subnets and the firewall
policy were kept and later weeks build on them.

---

## 1. Prerequisites

| Requirement | Detail |
| --- | --- |
| Organization | with a folder for platform projects and a folder for workloads |
| Host project | existing, with `compute` and `oslogin` APIs enabled (Week 1 supplies one) |
| Billing account | with a **free project slot** for the spoke |
| Quota project | with `cloudresourcemanager`, `serviceusage` and `cloudbilling` enabled |
| Terraform | &ge; 1.9, `hashicorp/google` `~> 6.0` |

### Permissions — and why CI cannot do all of this

| Need | Role | Scope |
| --- | --- | --- |
| enable Shared VPC host | `roles/compute.xpnAdmin` | **organization** — cannot be folder-scoped |
| create the network and subnets | `roles/compute.networkAdmin` | platform + workloads folders |
| create the instance | `roles/compute.instanceAdmin.v1` | workloads folder |
| create a firewall policy | `roles/compute.orgSecurityPolicyAdmin` | organization |
| **attach** that policy | `roles/compute.orgSecurityResourceAdmin` | workloads folder |

**`compute.xpnAdmin` cannot be folder-scoped** — host enablement is checked at
the organization, so it is the widest grant the pipeline holds. Week 02 was
amended by hand to add all of these, because an identity must not manage its own
grants.

---

## 2. Configuration

| Variable | Meaning |
| --- | --- |
| `org_id` | organization ID — **sensitive** |
| `host_project_id` | the Shared VPC host |
| `workloads_folder_id` | where the spoke project and firewall policy attach |
| `billing_account` | for the spoke project — **sensitive** |

---

## 3. Deploy

```bash
cd week-04-shared-vpc/terraform
terraform init
terraform plan      # expect: 14 to add
terraform apply
```

**Expected output:** `Apply complete! Resources: 14 added, 0 changed, 0 destroyed.`

| Resource group | Purpose |
| --- | --- |
| VPC + 2 subnets | custom-mode `hub`, with `dev-us-central1` and `prod-us-central1` |
| Shared VPC host + service attachment | makes the host a host, and attaches the spoke |
| Subnet IAM | lets the spoke's identities use one subnet, not the whole network |
| Hierarchical firewall policy + 2 rules + association | IAP ingress allowed, everything else denied |
| Spoke project + instance | one `e2-micro`, no external IP |
| API enablement | per project |

### The free-tier shape is four choices, not one

| Choice | Why |
| --- | --- |
| `e2-micro` | the only Always Free machine type |
| `us-central1` | one of three eligible regions |
| `pd-standard`, 10 GB | balanced or larger is billed |
| **no external IP** | an ephemeral public IP is billed per hour since 2020 |

**Changing any one of the four silently starts billing.** `validate.sh` asserts
all four.

---

## 4. Validate

```bash
ORG_ID=<ORG_ID> ./scripts/validate.sh
```

| Check | Expected | Actual 2026-09-12 |
| --- | --- | --- |
| Network is CUSTOM mode | not auto | custom |
| Shared VPC host enabled, spoke attached | both | both |
| Instance draws its address from the host's subnet | `10.20.0.2` | correct |
| Free-tier shape | all four conditions | all four |
| Firewall policy **attached**, not merely created | association present | attached |
| Week 03's exception is demonstrable | serial port enabled in `workloads/dev` only | demonstrated |
| Instance complies with what is now enforced | OS Login on, project SSH keys blocked | compliant |

**"Created" and "attached" are different things** for a hierarchical firewall
policy, and only the second one does anything. Check the association.

---

## 5. Cleanup

```bash
terraform destroy
```

**Expect this to fail the first time if constraints were promoted meanwhile.**
Week 03's `blockProjectSshKeys` was enforced after this lab deployed, and the
destroy then failed because Terraform wanted to remove
`block-project-ssh-keys=false` metadata added during testing — which the
now-enforced constraint refused to let go.

**Preserve:** the hub VPC, both subnets and the hierarchical firewall policy.
They occupy no project slot and Weeks 13–19 build on them. Only the spoke
(project, instance, attachment, subnet IAM) needs to go.

**Cost after teardown:** $0. A custom-mode VPC with no instances costs nothing.

---

## 6. Troubleshooting

### `Error 404: The resource 'projects/null' was not found`

**Cause.** A folder-scoped hierarchical firewall policy is owned by no project,
so the API has no project to bill the call to.

**Fix.** `user_project_override = true` plus `billing_project` on the provider.

**And it cascades.** Every call is then attributed to that quota project, which
must have `cloudresourcemanager`, `serviceusage` and `cloudbilling` enabled —
APIs it does not itself use. The first enablement is chicken-and-egg and has to
be done by hand.

### The firewall policy exists but nothing is filtered

**Cause.** `orgSecurityPolicyAdmin` carries
`firewallPolicies.create/update/use` but **not**
`organizations.setFirewallPolicy`. The policy was created and never associated.

**Fix.** Grant `roles/compute.orgSecurityResourceAdmin` on the folder, and assert
the association in validation rather than the policy's existence.

### A violation succeeded moments after a constraint was promoted

**Cause.** Enforcement lags the write — measured at 75–100 seconds in Week 03,
and the same lag applies to managed constraints.

**Fix.** Wait before validating. `validate.sh` waits 120 seconds.

**Also:** enforcement is **not retroactive**. Google's own denial text says a VM
already set to `block-project-ssh-keys=false` keeps access until its metadata
changes.

### `Cloud billing quota exceeded`

**Cause.** The billing account caps linked projects, at five here.

**Fix.** Unlink an unused project — and only the **owning** identity can unlink
one that sits outside the organization.

### Organization admin cannot see the instance, or read the firewall policy

**Cause.** `roles/resourcemanager.organizationAdmin` grants structure
administration, not resource visibility. Basic roles predate the hierarchy.

**Fix.** `roles/compute.instanceAdmin.v1` on the workloads folder to list the
VM; `roles/compute.orgFirewallPolicyUser` to read the policy. Both granted to the
human out of band.

---

## 7. Known limitations

- **The spoke no longer exists.** Week 05 destroyed it for a billing slot, so
  `validate.sh`'s instance checks no longer pass. The hub survives.
- **One spoke, one subnet.** Address exhaustion, subnet expansion and multi-spoke
  routing are untested.
- **`compute.xpnAdmin` is organization-scoped** and is the widest grant the
  pipeline holds. There is no narrower option.
- **No egress control.** Cloud NAT and egress policy arrive in Week 16.

---

## 8. For production

| Area | What would change |
| --- | --- |
| Address planning | Allocate ranges deliberately; `10.20.0.0/24` per environment does not survive growth |
| Egress | Cloud NAT plus an egress policy — this lab has no outbound path at all |
| Observability | Flow logs are on for one subnet only; they bill by volume once instances generate traffic |
| Separation | One service project per workload rather than per environment, so IAM and quota separate with it |

---

## 9. References

- [Shared VPC overview](https://docs.cloud.google.com/vpc/docs/shared-vpc)
- [Hierarchical firewall policies](https://docs.cloud.google.com/firewall/docs/firewall-policies)
- [Always Free usage limits](https://cloud.google.com/free/docs/free-cloud-features)
- [IAP for TCP forwarding](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding)

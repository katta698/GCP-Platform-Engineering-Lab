# Week 13 — reproduce it

How to deploy, validate and tear down HA VPN with BGP between two VPCs.
Background and the finding are in [README.md](./README.md).

## Prerequisites

| | |
| --- | --- |
| **Week 01** | The network hub project exists and `compute.googleapis.com` is enabled on it |
| **Week 04** | The `hub` VPC with the `dev-us-central1` subnet on `10.20.0.0/24` |
| **Week 02** | The federated pipeline — `tf-apply` assumed through Workload Identity Federation, no key |
| **Budget alert** | Set one before applying. Tunnels bill at $0.20/hr together |

### Permissions this week added

Week 02's `tf-apply` did not have enough to create a gateway or a VM. Both were
granted on the platform folder:

- `roles/compute.securityAdmin` — firewall rules
- `roles/compute.instanceAdmin.v1` — the probe VMs

Without them the apply fails partway, having already created the tunnels, which
bill while you work out what is missing.

## Environment

| | |
| --- | --- |
| Terraform | `>= 1.9` |
| `hashicorp/google` | `~> 6.0` |
| HCP workspace | `gcp-week-13`, organization `Katta`, project **GCP Platform Lab** |
| Execution | HCP Terraform, dynamic credentials via WIF |
| `gcloud` | Any current version. On Windows it emits CRLF — see the note at the end |

## Configuration

`terraform/terraform.tfvars` is gitignored. Create it with:

```hcl
net_hub_project_id = "<your network hub project>"
```

Everything else has a default:

| Variable | Default | Change it if |
| --- | --- | --- |
| `region` | `us-central1` | You want the probes outside the free tier |
| `branch_cidr` | `10.30.0.0/24` | It would overlap your hub ranges — BGP advertises both and an overlap makes the route ambiguous |
| `hub_asn` | `64512` | Must be private: 64512–65534 or 4200000000–4294967294 |
| `branch_asn` | `64513` | **Must differ from `hub_asn`.** Identical ASNs make this iBGP |
| `shared_secret` | none | Generated, never typed — see below |

Generate the pre-shared key:

```bash
./scripts/gen-psk.sh      # writes shared_secret into the gitignored tfvars
```

It prints confirmation, not the key. All four tunnels use the same secret,
which is what a GCP-to-GCP pair expects.

## Deploy

```bash
cd terraform
terraform init
terraform plan        # expect 22 to add
terraform apply
```

Tunnels take a minute or two to move from `FIRST_HANDSHAKE` to `ESTABLISHED`,
and BGP comes up after that. Validation immediately after the apply returns
will report sessions still coming up; wait and re-run rather than treating it
as a failure.

## Validate

```bash
./scripts/validate.sh
```

The counts are the point, not mere existence. **This script has not been run
against a live deployment:** it was written after the week was torn down, so
the block below is what it asserts, not output anyone has observed. Treat a
failure on the first run as a bug in the script until you have ruled that out
— Week 10's validate.sh asserted something false and died on an unset
variable, and both were found by running it rather than by writing it.

```
== Infrastructure deployed
  PASS  branch VPC exists
  PASS  hub HA VPN gateway exists
  PASS  branch HA VPN gateway exists
  PASS  hub gateway has 2 interfaces (2)
  PASS  four tunnel resources exist (4)

== Service functioning
  PASS  all four tunnels ESTABLISHED (4)
  PASS  hub router has 2 BGP sessions Established (2)
  PASS  branch router has 2 BGP sessions Established (2)

== The routes are learned, not written
  PASS  hub learned 10.30.0.0/24 twice (2)
  PASS  branch learned 10.20.0.0/24 twice (2)
  PASS  no static route to 10.30.0.0/24 exists

== Security controls
  PASS  branch firewall allows only the hub ranges
  PASS  hub probe has no external IP ()
  PASS  branch probe has no external IP ()
```

Two learned entries per prefix, one per tunnel. **One entry means one tunnel is
carrying everything** and the failover below has nowhere to go — that is a
failed deployment, not a quirk.

## Measure the failover

```bash
python scripts/measure-failover.py --trials 3 --json docs/failover.json
```

It disables one BGP peer, polls the hub router until the route learned through
that tunnel is withdrawn, re-enables it, and waits for the route to return.
Both directions are timed, and the tunnel is restored in a `finally` block on
every path out including an exception.

Observed here: **withdrawn in 3.1–3.6s** across three trials.

If it reports `no withdrawal observed`, that is a failed measurement, not a
finding — check that two routes were learned before the trial started. The
script aborts up front if fewer than two sessions are Established, for exactly
that reason.

## Teardown

```bash
cd terraform
terraform destroy
```

Verify nothing is left — the tunnels are what bill:

```bash
gcloud compute vpn-tunnels list --project="$PROJECT" --format='value(name)'
gcloud compute vpn-gateways list --project="$PROJECT" --format='value(name)'
gcloud compute routers list --project="$PROJECT" --format='value(name)'
gcloud compute instances list --project="$PROJECT" --format='value(name)'
```

All four must return nothing. The hub VPC and its subnets survive — they are
Week 04's and this week only read them.

`terraform destroy` removes everything this week created; there is no
equivalent of Week 12's KMS problem where a destroy reports success and leaves
a billable object behind.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Tunnels stay `FIRST_HANDSHAKE` | The two gateways disagree on the pre-shared key | Re-run `gen-psk.sh` and apply; all four tunnels need the same secret |
| BGP stuck in `Connect` | ASNs identical on both sides | `branch_asn` must differ from `hub_asn` |
| Only one route learned per prefix | One tunnel is down | Check `vpn-tunnels list` for a tunnel not `ESTABLISHED` |
| Apply fails creating a firewall rule or VM | `tf-apply` lacks `compute.securityAdmin` or `compute.instanceAdmin.v1` | Grant both on the platform folder, then re-apply |
| VM creation fails with Error 412 | Week 03's org policies require OS Login and block project SSH keys | The metadata is already set in `main.tf`; this bites a VM you add by hand |
| The Cloud Router console says "You need additional access" | Console-only permission behaviour | The same reads succeed from the CLI as the same identity. Use `routers get-status` |
| A string compare fails against output that looks correct | `gcloud` on Windows emits CRLF | Pipe through `tr -d '\r'`, as `validate.sh` does |

## Known limitations and what production changes

- **Both VPCs are in one project and one region.** A real hybrid link terminates
  on hardware or another cloud, and the peer would be `peer_external_gateway`
  rather than `peer_gcp_gateway`. The protocols and the failover behaviour are
  identical; what changes is who owns the far end.
- **One region.** Production would place the gateways in two regions so a
  regional failure is survivable, not just a tunnel failure.
- **A static pre-shared key in tfvars.** Production would hold it in Secret
  Manager and reference it, which is Week 12's machinery.
- **No alerting.** A tunnel that drops and stays down is invisible here. A real
  deployment alerts on `vpn_tunnel/status` and on BGP session state, because
  the whole value of the second tunnel is that nobody notices the first one
  failing — including you.
- **MED and route priority are left at defaults.** Both tunnels are equal cost,
  so traffic uses both. Production often prefers one path and keeps the other
  warm, which is a different advertisement, not a different topology.

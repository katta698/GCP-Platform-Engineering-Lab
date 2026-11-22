# Week 14 — reproduce it

Deploy a Private Service Connect endpoint for Google APIs alongside Private
Google Access, prove they are not the same thing, and tear it down. Background
and the finding are in [README.md](./README.md).

## Prerequisites

| | |
| --- | --- |
| **Week 01** | The network hub project, with `compute.googleapis.com` enabled |
| **Week 02** | The federated pipeline — `tf-apply` through Workload Identity Federation, no key |
| **IAP** | `gcloud compute ssh --tunnel-through-iap` must work; the probe has no public address |
| **Budget alert** | One exists on the billing account. It alerts; it does not cap. See `docs/COST-GUARDRAILS.md` |

No permissions were added this week. Week 13's grants
(`compute.securityAdmin`, `compute.instanceAdmin.v1` on the platform folder)
were already sufficient.

## Environment

| | |
| --- | --- |
| Terraform | `>= 1.9` (ran on 1.14.8) |
| `hashicorp/google` | `~> 6.0` |
| HCP workspace | `gcp-week-14`, organization `Katta`, project **GCP Platform Lab** |
| Execution | HCP Terraform, remote, WIF dynamic credentials |
| `gcloud` | Any current version. On Windows it emits CRLF — the scripts strip it |

**If a new workspace cannot authenticate**, it is almost certainly not in the
GCP Platform Lab project. `terraform init` creates workspaces in HCP's *Default
Project*, which does not inherit the `gcp-wif-credentials` variable set, and
the failure appears as a Google ADC error that points nowhere near the cause.
Move the workspace into GCP Platform Lab.

## Configuration

`terraform/terraform.tfvars` is gitignored:

```hcl
net_hub_project_id = "<your network hub project>"
```

| Variable | Default | Change it if |
| --- | --- | --- |
| `region` | `us-central1` | You want the probe outside the free tier |
| `subnet_cidr` | `10.40.0.0/24` | It would overlap the hub's `10.20.x` ranges |
| `endpoint_ip` | `10.99.0.2` | **Must sit outside every subnet range in this VPC.** Google rejects an address inside one |

## Deploy

```bash
cd terraform
terraform init
terraform plan        # expect 6 to add
terraform apply
```

## Validate

```bash
./scripts/validate.sh
```

Expected — and this is **observed output**, not a prediction; the script ran
against this deployment:

```
== Infrastructure deployed
  PASS  network psc-lab exists
  PASS  subnet psc-lab-us-central1 exists
  PASS  forwarding rule pscapis exists

== Private Google Access is on, because it is half the comparison
  PASS  subnet has privateIpGoogleAccess (True)

== The endpoint address is ours, and is not a Google VIP
  PASS  address purpose is PRIVATE_SERVICE_CONNECT (PRIVATE_SERVICE_CONNECT)
  PASS  forwarding rule targets all-apis (all-apis)
  PASS  endpoint address is 10.99.0.2
  PASS  endpoint sits outside every subnet range (10.40.0.0/24)

== The client has nothing of its own
  PASS  probe has no external IP (empty)
  PASS  probe is in psc-lab-us-central1 (psc-lab-us-central1)
  PASS  no Cloud Router or NAT on psc-lab

== The route the comparison turns on
  PASS  default internet-gateway route present: default-route-<hash>

12 passed, 0 failed
```

The NAT assertion matters more than it looks: with a Cloud NAT on the network,
both paths would work regardless of mechanism and the whole comparison would
prove nothing.

## Measure

```bash
./scripts/break-pga.sh --json docs/pga-vs-psc.json
```

It runs the same HTTPS call to the same API twice from the same VM — once on
default DNS (a Google public VIP, which is Private Google Access) and once with
`--resolve` pinning the connection to the endpoint. Then it deletes the
default internet-gateway route, repeats both, restores the route, and repeats
again.

Observed:

```
baseline:       Private Google Access -> 401   PSC endpoint -> 401
route deleted:  Private Google Access -> 000   PSC endpoint -> 401
route restored: Private Google Access -> 401   PSC endpoint -> 401
```

It aborts if both paths do not work at baseline, so a broken deployment cannot
be written up as a finding.

## Teardown

```bash
cd terraform
terraform destroy
```

**This fails the first time if you ran `break-pga.sh`.** The default route is
created by Google when the network is created, so Terraform never owned it;
once the script has recreated it by hand, the network cannot be deleted:

```
Error: The network resource '...psc-lab' is already being used by
'...routes/default-route-<hash>'
```

Delete the route, then destroy again:

```bash
gcloud compute routes delete default-route-<hash> --project="$PROJECT" --quiet
terraform destroy
```

Nothing bills in the meantime — a network and a route are free. Verify:

```bash
python ../scripts/check_nothing_running.py
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Invalid value for field 'resource.name': 'psc-apis'` | A PSC-to-Google-APIs forwarding rule name takes lowercase letters and digits only, 1–20 chars | Use `pscapis` |
| Apply fails with a Google ADC error on a brand-new workspace | The workspace is in HCP's Default Project and inherits no credentials | Move it to GCP Platform Lab |
| `Invalid list filter expression` from `gcloud compute routes list` | That three-term server-side filter is rejected | Filter on the network only and select client-side |
| `validate.sh` stops silently after a section header | `set -e` plus a failing `gcloud` in a command substitution | Run the failing command alone to see its error |
| Status codes read `000000` | `curl` already prints `000` on failure; a `|| echo 000` fallback doubles it | Take the last three characters |
| `Browser context management is not supported` when capturing | Another lab's Chrome holds `127.0.0.1:9222`; ours is on `[::1]:9222` | The capture scripts now try both |

## Known limitations and what production changes

- **One VPC, one region.** The interesting case is reaching the endpoint from
  on-premises over Cloud VPN, which is where PSC genuinely beats Private Google
  Access. That needs a Cloud DNS inbound forwarding policy so hybrid clients
  resolve the name, and was not built here.
- **`--resolve` instead of DNS.** Real clients should not need a curl flag. In
  production a private DNS zone maps `storage.googleapis.com` to the endpoint
  so existing code uses it unmodified. The flag keeps the comparison honest in
  one VM — both calls can run side by side.
- **`all-apis`, not `vpc-sc`.** The `vpc-sc` bundle restricts the endpoint to
  APIs that support VPC Service Controls, which is what you want inside a
  perimeter. That is Week 19.
- **No VPC Service Controls perimeter.** Without one, a workload with other
  routes could still reach the internet. This week removes the route; a
  perimeter removes the possibility.
- **The probe proves reachability, not authorisation.** Every call returned
  401. A real workload would carry a service account and the response would be
  200, which tests IAM rather than the network path.

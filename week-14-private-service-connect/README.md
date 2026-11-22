# Week 14 — Private access to Google APIs, with no route to the internet

A workload that is not allowed to reach the internet still needs to call Google
APIs. This week gives it a supported path, and then proves the guarantee by
deleting the internet route and showing the workload carries on working.

## What this gives app teams

| Capability | Who consumes it | What it replaces | What it costs them |
| --- | --- | --- | --- |
| Reach Google APIs from a VM with no external IP and no internet route | Any team running under a no-egress rule | A ticket to networking, a NAT exception, or an argument with an auditor | Nothing to configure — the subnet and endpoint are platform-owned |
| A re-runnable answer to "prove it cannot reach the internet" | Risk, audit, compliance | An assertion in a design document | One command they can run themselves |

## Cost note

| What runs continuously | Rate | Notes |
| --- | --- | --- |
| 1 Private Service Connect endpoint | $0.01/hr | No data-transfer charge for Google APIs, unlike an endpoint to a published service |
| 1 e2-micro probe, no external IP | free tier | `us-central1`, within the monthly allowance |
| VPC, subnet, routes, firewall rule | no charge | |

**Measured cost: not yet available.** The week ran about 1.2 hours and the
charges had not posted when this was written. Read it from the billing export
once they settle, not from the rate card — and attach the time it was read.
Week 13's export returned $1.76 at 22:40 and $1.99 at 23:20 on the same day.

The teardown removes everything: the endpoint, the reserved address, the probe,
the firewall rule, the subnet and the VPC. **One manual step** — see LAB.md:
`break-pga.sh` recreates the default route by hand, and Terraform cannot delete
a network while a route it does not own still references it.

## What it builds

| Resource | Count | Job |
| --- | --- | --- |
| `google_compute_network` | 1 | Its own VPC, so deleting the default route harms nothing else |
| `google_compute_subnetwork` | 1 | `private_ip_google_access = true` — this flag *is* Private Google Access |
| `google_compute_global_address` | 1 | `PRIVATE_SERVICE_CONNECT`, outside every subnet range |
| `google_compute_global_forwarding_rule` | 1 | `target = "all-apis"` — the endpoint itself |
| `google_compute_firewall` | 1 | IAP range only; the VM has no public address |
| `google_compute_instance` | 1 | e2-micro, no external IP, no NAT |

6 resources.

## The finding

| Stage | Private Google Access | PSC endpoint |
| --- | --- | --- |
| baseline | 401 | 401 |
| default internet-gateway route deleted | **000** | **401** |
| route restored | 401 | 401 |

Same API, same VM, same minute. The only difference is which address `curl`
connects to. `401` means the call reached Google and was refused for lack of
credentials — the path works. `000` means the connection never opened.

Deleting one route killed Private Google Access and the PSC endpoint did not
notice, because it never used that route: `10.99.0.2` is inside the VPC.

Measurement in `docs/pga-vs-psc.json`, produced by `scripts/break-pga.sh`,
which restores the route in a trap on every exit path.

## Running it

See [LAB.md](./LAB.md).

## Things worth knowing before you build this

- **"Private" in Private Google Access means the VM has no external IP.** It
  does not mean the traffic avoids Google's public addresses — it goes to
  `199.36.153.8/30` out through the default internet gateway, which is exactly
  why deleting that route breaks it.
- **The endpoint address must sit OUTSIDE every subnet range.** Google rejects
  one inside: it "can't be within the range of subnets configured in the VPC
  network". The endpoint is `10.99.0.2`; the subnet is `10.40.0.0/24`.
- **A PSC-to-Google-APIs forwarding rule name takes lowercase letters and
  digits only** — 1–20 characters, starting with a letter. No hyphens.
  `psc-apis` is rejected with Error 400 naming the field; `pscapis` is fine.
- **A PSC endpoint is reachable from on-premises over Cloud VPN or
  Interconnect, and is NOT reachable through VPC Network Peering.** Private
  Google Access supports neither. That difference, not the price, is usually
  what decides between them.
- **Endpoints created before 2026-09-01 are unsupported inside VPC Service
  Controls perimeters** and must be recreated. It appears on the configuration
  page, never on the product overview.

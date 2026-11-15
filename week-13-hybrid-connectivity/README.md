# Week 13 — Hybrid connectivity: HA VPN and BGP

Two VPCs joined by two IPsec tunnels, with BGP deciding the routing. Then one
tunnel is broken on purpose to show that nothing has to be re-typed for traffic
to keep moving.

**Blog:** https://jayanthkatta.com/blog/week-13-hybrid-connectivity/

## Cost note

| What runs continuously | Rate | Notes |
| --- | --- | --- |
| 4 VPN tunnel resources | $0.05/hr each | **$0.20/hr together.** Four resources, two logical tunnels — each end of each tunnel bills |
| 4 external IPs on the gateways | included *while in use* | An address assigned to a gateway but **not** used by a tunnel bills hourly |
| 2 Cloud Routers | no charge | Control plane only |
| 2 e2-micro probes, no external IP | free tier | `us-central1`, within the monthly allowance |
| Egress between the two VPCs | per GB | Negligible at ping volume |

**Measured cost for this week: $1.76 gross, $1.72 after credits**, read from
the billing export on 2026-11-14. The tunnels are $1.72 of it. The two probes
net to zero — they bill and then carry an equal free-tier discount, which is
why a query filtered to `cost > 0` overstates the week.

The teardown removes everything: both gateways, all four tunnels, both routers
and their BGP peers, the branch VPC and subnet, both firewall rules and both
probes. The hub VPC is **Week 04's and is not touched** — this week reads it as
a data source and adds a gateway and a router to it.

**Set a budget alert before deploying.** At $0.20/hr this is the most expensive
week in the lab so far, and tunnels bill whether or not anything is sent
through them.

## What it builds

| Resource | Count | Job |
| --- | --- | --- |
| `google_compute_network` / `subnetwork` | 1 + 1 | The branch VPC, standing in for a remote site |
| `google_compute_ha_vpn_gateway` | 2 | Two interfaces each; one interface carries no SLA |
| `google_compute_router` | 2 | BGP on ASN 64512 and 64513 |
| `google_compute_vpn_tunnel` | 4 | Interface 0 to 0 and 1 to 1, seen from both ends |
| `google_compute_router_interface` | 4 | Link-local /30 per tunnel per side |
| `google_compute_router_peer` | 4 | The BGP session itself |
| `google_compute_firewall` | 2 | ICMP and SSH from the far side only |
| `google_compute_instance` | 2 | Probes, no external IP |

22 resource instances from 16 resource blocks.

## The finding

Routes learned through a tunnel are withdrawn **3.1–3.6s** after it drops,
measured across three trials, and the surviving tunnel carries the prefix
throughout. Nobody edits a route table. A static route cannot do this — it
points at a dead tunnel as confidently as a live one.

The measurement is in `docs/failover.json`, produced by
`scripts/measure-failover.py`, which restores the tunnel on every path out.

## Running it

See [LAB.md](./LAB.md) for prerequisites, variables, the deploy sequence and
the teardown.

## Things worth knowing before you build this

- **A single active interface carries no availability SLA**, not a reduced one.
  99.99% requires two interfaces, two tunnels and two peer addresses.
- **Classic VPN is not deprecated.** The docs recommend HA VPN and carry no
  deprecation notice; Classic VPN still has its own 99.9% SLA. Recommended-
  against is not deprecated.
- **The two ASNs must differ.** Identical ASNs on both ends make this an iBGP
  session, which does not re-advertise learned routes the way this topology
  needs.
- **HA VPN tunnels have no enable/disable verb.** Disabling the BGP peer
  (`--no-enabled` on `routers update-bgp-peer`) is the closest reversible
  equivalent and exercises the same withdrawal path.
- **The Cloud Router is not in the data path.** It programs routes; traffic
  does not flow through it.

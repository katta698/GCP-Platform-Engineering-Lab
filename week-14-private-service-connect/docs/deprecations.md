# Week 14 — deprecation status of every service used

Read from the deprecation and release-note pages, not inferred from a clean
product page. Checked 2026-11-20, before any Terraform was written.

| Service | Deprecation page consulted | Checked | Status |
| --- | --- | --- | --- |
| Private Service Connect | https://docs.cloud.google.com/vpc/docs/private-service-connect | 2026-11-20 | current. Three variants exist and the names are unchanged: endpoints, backends, interfaces. No deprecation or rename notice |
| PSC endpoints for Google APIs | https://docs.cloud.google.com/vpc/docs/configure-private-service-connect-apis | 2026-11-20 | current. One dated change: endpoints created before 2026-09-01 are unsupported inside VPC Service Controls perimeters and must be recreated. This week creates new ones, so it is unaffected |
| Private Google Access | https://docs.cloud.google.com/vpc/docs/private-google-access | 2026-11-20 | current, no deprecation. Still a per-subnet setting, still requires a route whose next hop is the default internet gateway |
| Private services access | https://docs.cloud.google.com/vpc/docs/private-access-options | 2026-11-20 | current, and explicitly NOT the mechanism for Google APIs — it is VPC peering to a producer network. Not used this week |
| Compute Engine (probe VM) | https://docs.cloud.google.com/compute/docs/deprecations | 2026-11-20 | e2 family current; no deprecation affecting e2-micro in us-central1 |
| Cloud VPN / Cloud Router | https://docs.cloud.google.com/network-connectivity/docs/vpn/deprecations/classic-vpn-deprecation | 2026-11-20 | carried over from Week 13: BGP on Classic VPN ended 2025-08-01; HA VPN unaffected. Only relevant if the hybrid variant is built |

## The one dated item worth repeating

PSC endpoints for Google APIs created **before 2026-09-01** are not supported
in VPC Service Controls perimeters and have to be recreated. It is not a
deprecation of the feature, and it does not touch this week, but it is the kind
of line that only appears on the configuration page - the product overview says
nothing about it.

## What the pages settled that changes the week's framing

Private Google Access and a PSC endpoint are not two spellings of the same
thing, and the difference is the whole lab:

- **Private Google Access** sends traffic to "the standard external IP
  addresses or Private Google Access domains and VIPs for Google APIs and
  services through the VPC network's default internet gateway". It is a per
  subnet setting, it needs that default route, and it supports "Google Cloud
  resources without external IP addresses" only.
- **A PSC endpoint** is an internal IP address in the consumer VPC network.
  It works "with or without external IP addresses", and it can be reached from
  "supported connected on-premises hosts" over Cloud VPN or Interconnect.
- Neither is reachable **through VPC Network Peering**: the endpoint features
  table lists "Access through VPC Network Peering" as "No".

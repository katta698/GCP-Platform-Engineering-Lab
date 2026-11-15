# Week 13 — deprecation status of every service used

Read, not inferred. Checked against Google's own deprecation pages rather than
by looking at a product overview and seeing no banner — which is how this week
came to publish "Classic VPN is not deprecated" while BGP on it had been
deprecated for fifteen months.

| Service | Deprecation page consulted | Checked | Status |
| --- | --- | --- | --- |
| HA VPN | https://docs.cloud.google.com/network-connectivity/docs/vpn/concepts/overview | 2026-11-15 | current and recommended; 99.99% SLA for most topologies. No deprecation page exists for HA VPN |
| Classic VPN | https://docs.cloud.google.com/network-connectivity/docs/vpn/deprecations/classic-vpn-deprecation | 2026-11-15 | the product is NOT deprecated and keeps a 99.9% SLA for static routing, but dynamic routing (BGP) was deprecated 2025-08-01: new BGP tunnels cannot be created and existing ones run without an SLA |
| Cloud Router | https://docs.cloud.google.com/network-connectivity/docs/router/concepts/overview | 2026-11-15 | current. Its BGP role on HA VPN is unaffected by the Classic VPN deprecation; only Classic VPN as a peer is |
| Cloud VPN (tunnels, IKEv2) | https://docs.cloud.google.com/network-connectivity/docs/vpn/release-notes | 2026-11-15 | no deprecation affecting IKEv2 tunnels between HA VPN gateways |
| Compute Engine (e2-micro probes) | https://docs.cloud.google.com/compute/docs/deprecations | 2026-11-15 | e2 machine family current; no deprecation affecting e2-micro in us-central1 |

## What this week is exposed to

The Classic VPN row is the one that matters and it is **not** a risk to this
build: the week uses `google_compute_ha_vpn_gateway` throughout and creates no
Classic VPN resource. The deprecation closes the alternative, which makes the
week's choice the only remaining way to run BGP against Google — a stronger
argument for HA VPN than the SLA comparison the post originally made.

## Why the first pass missed it

The briefing read `vpn/concepts/overview`, found no deprecation notice, and
concluded Classic VPN was current. That page describes the product and does not
carry the deprecation; the deprecation has its own page under `vpn/deprecations/`
which nothing on the overview makes obvious. Searching the product page is not
searching the deprecations index.

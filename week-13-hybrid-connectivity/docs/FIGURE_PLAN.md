# Figure plan — Week 13

**Goal in one sentence:** build HA VPN between two VPCs and show that BGP, not a
static route, is what makes the "HA" real — by killing a tunnel and watching the
routes move.

**Prerequisites:** the hub VPC (Week 04); the federated pipeline (Week 02), plus
a Week 02 amendment granting `compute.securityAdmin` and
`compute.instanceAdmin.v1` on the platform folder.

Slots are numbered in the order a reader performs the steps. Written before
capturing. Retired slots go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-repo-structure.png` | rendered card | major directories and what each is responsible for | matches the committed `.card` |
| 02 | `02-tunnels-up.png` | GCP console | all four tunnels established, both gateways, both routers | **perishable** — this view stops being true the moment slot 05 runs |
| 03 | `03-bgp-established.png` | GCP console | both BGP sessions on the hub router, state Established | two sessions, not one — a single interface carries no SLA |
| 04 | `04-routes-learned.png` | terminal card | `10.30.0.0/24` learned twice, once per tunnel, and nothing static | the route exists in the table and appears in no `.tf` file |
| 05 | `05-failover.png` | terminal card | one tunnel disabled, BGP withdrawing its routes, ping unbroken | **the post** — route count halves, traffic continues, measured |
| 06 | `06-cost.png` | console / BigQuery | the actual charge for the hours it ran | **cost slot — exempt**; charges post about a day later |
| 07 | `07-hcp-apply.png` | HCP Terraform | the workspace run list: 3 applied, 2 errored | the deployment mechanism, and the two failures that shaped the week |

## Reader order in the published post

Corrected 2026-11-15 after Jay asked why the deploy screenshot sat at Step 4
while Steps 2 and 3 already showed established tunnels and learned routes.
They did, and nothing in the narrative had created them yet.

| Post step | Shows | Slot |
| --- | --- | --- |
| 1-3 | the Terraform, written | *(code, no figure)* |
| 4 | the apply that made it real | 07 |
| 5 | four tunnels, established | 02 |
| 6 | the route nobody wrote | 04 |

**Slot numbers are now out of step with reader order**, and they stay that way:
numbers are never recycled. The cause is on the record - slot 07 was added
after the plan was written, in the commit "add the HCP run figure that should
have been planned". A deploy figure belongs near the start of the sequence and
was not planned at all, which is the same omission that put it after its own
evidence in the post.

## Capture order

**02 and 03 first, before anything is broken.** They are the only views of a
healthy four-tunnel topology, and slot 05 destroys that state deliberately.

## Why these six

**05 is the post.** Everything before it is setup. The claim is that BGP makes
HA real — that a dead tunnel is noticed and routed around without anyone
touching a route table. The only honest evidence is the same ping continuing
across a tunnel going down, with the route count visibly halving.

**04 exists to prove the route is dynamic.** A reader cannot tell a learned
route from a typed one by looking at a route table. Showing it alongside a
grep of the Terraform that does not contain it is what makes the point.

**02 and 03 are console because a single moment is the evidence.** Four tunnels
established and two BGP sessions up is a state, not a sequence.

## No figure for

- The VPC and subnet existing. The Terraform run proves it, and a list with one
  row shows no idea.
- The VMs. They are instruments, not the subject.
- The HCP run. Every week has one and it carries nothing specific to this week.

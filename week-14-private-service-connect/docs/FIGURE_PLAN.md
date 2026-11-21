# Figure plan — Week 14

**Goal in one sentence:** give a workload that is not allowed to reach the
internet a supported path to Google APIs, and prove the guarantee by deleting
the internet route and showing the workload carries on working.

**What this gives app teams**

| Capability | Who consumes it | What it replaces | What it costs them |
| --- | --- | --- | --- |
| Reach Google APIs from a VM with no external IP and no internet route | Any team running a workload under a no-egress rule | A ticket to networking, a NAT exception, or an argument with an auditor | Nothing to configure; the subnet and endpoint are platform-owned |
| A written answer to "prove it cannot reach the internet" | Risk, audit, compliance | An assertion in a design document | One command they can re-run themselves |

**Why a customer pays for this.** "No egress to the internet" is a control
auditors ask for and architects usually answer with a diagram. The difference
between Private Google Access and a Private Service Connect endpoint decides
whether that answer survives the route being removed — which is the closest
thing to an audit this lab can run. It is also the on-ramp to the VPC Service
Controls perimeter in Week 19.

**Prerequisites:** the hub VPC (Week 04); the federated pipeline (Week 02).

Slots are numbered in the order a reader performs the steps, and the deploy
comes before anything it produced. Written before any Terraform. Retired slots
go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-repo-structure.png` | rendered card | major directories and what each is responsible for | matches the committed `.card` |
| 02 | `02-hcp-apply.png` | HCP Terraform | the workspace run list for the apply that created everything | the deploy, before any evidence it produced |
| 03 | `03-endpoint-address.png` | terminal card | the reserved address with `purpose: PRIVATE_SERVICE_CONNECT`, shown beside the subnet range it is deliberately OUTSIDE | the address is ours and is not a Google VIP |
| 04 | `04-both-paths-work.png` | terminal card | from the VM with no external IP: a call over the PSC endpoint AND a call over Private Google Access, both succeeding | **perishable** - the only view of both paths working, and slot 05 destroys it |
| 05 | `05-route-deleted.png` | terminal card | default internet gateway route removed; PGA call fails, PSC call still succeeds | **the post** — one mechanism needed that route and the other never did |
| 06 | `06-route-restored.png` | terminal card | route back, PGA working again | the control was degraded reversibly, and restored |
| 07 | `07-cost.png` | BigQuery billing export | what the endpoint actually cost | **cost slot — exempt**; charges settle about a day later |

## Perishable

**Slot 04 is perishable.** It is the only view of both paths working at once,
and slot 05 destroys that state deliberately. It must be captured at the apply,
with the real command output teed into `docs/evidence/04-both-paths-work.txt`
and a `# captured <UTC>` first line — `check_capture_timing.py` fails the
teardown otherwise.

Write `docs/evidence/_deployed.txt` at the apply so the captures can be timed
against it.

## Why these seven

**05 is the post.** Everything before it is setup. The claim an app team cares
about is "this workload cannot reach the internet, and still works". The claim
a platform engineer has to get right underneath it is that "private" in Private
Google Access means the VM has no external IP — not that the traffic avoids
Google's public addresses. The honest evidence is the same two calls, run again
after the route they share is gone, with one of them failing.

**06 exists because a lab that degrades a control restores it.** It is also
the only proof the failure in 05 was caused by the route and nothing else.

**03 proves the address is ours.** A reader cannot tell a PSC endpoint IP from
any other internal address by looking at it. The reservation carries
`purpose: PRIVATE_SERVICE_CONNECT`, and the IP sits deliberately OUTSIDE every
subnet range - the docs require it: the address "can't be within the range of
subnets configured in the VPC network". Shown next to Private Google Access's
`199.36.153.8/30`, which is Google's, the difference stops being a claim.

## No figure for

- The VM existing. The Terraform run proves it.
- The firewall rule. An IAP range in a list shows no idea.
- The subnet's `private_ip_google_access` flag on its own — it is a boolean in
  a console page, and slot 05 is what gives it meaning.

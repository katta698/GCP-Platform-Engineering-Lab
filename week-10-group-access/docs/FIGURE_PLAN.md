# Figure plan — Week 10

**Goal in one sentence:** make a role in this organization be held by a group
instead of a person, and prove that access appears and disappears with group
membership and nothing else.

**Prerequisites:** Cloud Identity on the domain (live since Week 01),
`cloudidentity.googleapis.com` enabled on the seed project (enabled 2026-10-23),
and `tf-apply` holding groups-admin authorization in the Admin console — a
Workspace admin role, not a GCP IAM role.

Slots are numbered in **the order a reader performs the steps**. Written before
capturing. Retired slots go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-groups-before.png` | Admin console | the Groups list, **empty** | zero groups listed |
| 02 | `02-terraform-layout.png` | rendered card | every file, its job and line count | 6 resource blocks |
| 03 | `03-hcp-apply.png` | HCP console | the run that applied it | **Applied**, 6 resources |
| 04 | `04-folder-iam-group.png` | GCP console | folder IAM with a **group** as the principal holding `roles/logging.viewer` | principal is a group, not a user |
| 05 | `05-access-revocation.png` | terminal card | the subject reading logs, membership removed, the same command denied | permitted → denied → permitted, with the measured delay each way |

## Why these five

**05 is the post.** Everything else is context: a group existing proves nothing,
and CLAUDE.md is explicit that identity objects rarely earn a figure. What earns
one is the *indirection working* — the same command, the same principal, two
different answers either side of a membership change. A terminal is the honest
surface for that, because the evidence is a timed sequence of commands and their
exit states, not a page.

**01 is perishable** — the empty Groups list cannot be recaptured once the apply
creates a group, so it is taken before anything is deployed.

**04 is the only console figure that carries an idea** rather than an existence
proof: the principal column reading a group address instead of a person is the
entire architectural change, visible in one line.

**02 can never be lost to a teardown**, which is why every week carries it.

## What is deliberately not a figure

- **The group itself, in the Admin console, with its one member.** It proves the
  resource exists, which the Terraform run already proves. The membership only
  becomes interesting when it is *removed*, and that is slot 05.
- **The service account.** An identity object that shows nothing; it matters
  only that it holds no direct role, which is a policy read, not a picture.
- **The API enablement.** One line in a service list.
- **Cost.** $0, and nothing to photograph. Cloud Identity Free.

## Measurement this week owes

Google documents a propagation delay for group membership arriving **from an
external IdP** and says it can take up to several hours. There is no external
IdP here — membership is written directly through the Cloud Identity API — so
that figure does not describe this configuration and must not be quoted for it.

The delay in THIS setup is unmeasured. Measure it the way Week 03 measured org
policy enforcement lag: three trials each direction, ten-second poll, grant and
revoke, and publish the range rather than one observation. One success followed
by one failure is not a measurement.

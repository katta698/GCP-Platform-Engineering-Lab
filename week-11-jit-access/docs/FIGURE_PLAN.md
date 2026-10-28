# Figure plan — Week 11

**Goal in one sentence:** make a privileged role something a principal *requests
and loses* rather than something it holds, and measure how long the binding
actually takes to disappear after the grant expires.

**Prerequisites:** the folder hierarchy (Week 01), the federated pipeline
(Week 02), and a Week 02 amendment granting `tf-apply`
`roles/privilegedaccessmanager.admin` — it already holds
`roles/resourcemanager.folderAdmin`, which folder-level entitlements also
require. `privilegedaccessmanager.googleapis.com` is **not** enabled on the seed
project as of 2026-10-28 and this week enables it.

Slots are numbered in **the order a reader performs the steps**. Written before
capturing. Retired slots go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-denied-before.png` | terminal card | the subject reading the platform folder's IAM policy and being refused | `PERMISSION_DENIED`, before any entitlement exists |
| 02 | `02-repo-structure.png` | rendered card | major directories and what each is responsible for | matches the committed `.card` |
| 03 | `03-entitlement.png` | GCP console | the entitlement: eligible requester, approver, max duration, the role it grants | access defined as a **template**, with no binding yet in the folder's IAM policy |
| 04 | `04-grant-pending.png` | GCP console | a grant requested and **waiting on approval** | state is `AWAITING_APPROVAL`, requester ≠ approver |
| 05 | `05-granted.png` | terminal card | the same command now succeeding, and the binding present in the folder policy | permitted, and the policy carries a binding nobody wrote in Terraform |
| 06 | `06-expired.png` | terminal card | after expiry: binding gone, same command refused again, with the measured lag | `PERMISSION_DENIED` returns; removal observed, not assumed |

## Why these six

**06 is the post.** Everything before it is setup. The claim PAM actually makes
is that access ends *without anybody remembering to end it*, and the only honest
evidence for that is the same command, the same principal, refused again after a
timer nobody touched — plus a number for how long the removal took. A terminal
is the right surface, because the evidence is a timed sequence of commands and
their exit states, not a page.

**01 and 06 are the same command.** That is deliberate: the before/after pair is
what makes 05 mean something. A grant that works proves nothing on its own.

**04 is the only console figure carrying an idea** rather than an existence
proof — a request sitting in `AWAITING_APPROVAL` is the two-party control
visible in one line. It is also why the requester is a **service account the
operator impersonates** and the approver is the human: if one principal both
requests and approves, the approval step is a form filled in twice and the
figure proves nothing.

**03 shows the template/instance split**, which is the concept the week turns
on: an entitlement is not a grant. It is a description of access that *may* be
requested, and until someone requests it the folder's IAM policy is unchanged.

**02 can never be lost to a teardown**, which is why every week carries it.

## What is deliberately not a figure

- **The HCP run reaching Applied.** An existence proof; the run already proves
  the resources exist, and CLAUDE.md is explicit that this does not earn a
  figure. Weeks 06 and 10 retired the same slot.
- **The service account.** An identity object that shows nothing. What matters
  is that it holds no standing role, which is a policy read — slot 01.
- **The API enablement.** One line in a service list.
- **Cost.** $0. PAM has no charge of its own and this week creates no billable
  resource.

## Measurement this week owes

**How long after expiry the role binding actually leaves the folder's IAM
policy.** Unmeasured anywhere I can find, and it is the operationally
interesting number: if removal lags, "access ended" is false for a window
nobody documents.

Measure it the way Week 03 measured organization policy enforcement lag: poll
the folder's IAM policy every ten seconds across the expiry boundary, three
trials, and publish the range rather than one observation. One success followed
by one failure is not a measurement.

**Each trial costs at least 30 minutes of wall clock.** Google's documented
range for `max_request_duration` is 1800s to 604800s, so **30 minutes is the
shortest access PAM will grant**. That is itself worth stating: you cannot hand
someone five minutes of elevated access.

## Constraints that shaped the design

- **IAM Recommender is not in this week.** Role recommendations for non-basic
  roles, custom-role suggestions and policy insights require Security Command
  Center Premium or Enterprise. Every grant in this lab is a predefined role, so
  the free tier would return nothing. The week demonstrates the *mechanism* for
  temporary access and does not claim evidence that the estate needed it.
- **Multi-party approval is Preview and also needs Premium/Enterprise.** This
  week uses the standard single-approver workflow, with requester and approver
  as different principals so the step is still real.

# Week 11 — Just-in-time privileged access

**Status: in progress.** Built and validated offline; **not yet deployed**, and
not published. Nothing in this folder has been applied against the organization.

## Cost note

**$0.** Privileged Access Manager has no charge of its own, and this week
creates no billable resource: an API enablement, a service account, one IAM
binding scoped to that account, and one entitlement. Nothing runs continuously
and nothing bills per hour.

**Not in this week, deliberately:** the IAM recommender's role recommendations
for non-basic roles, its custom-role suggestions and its policy insights all
require Security Command Center **Premium or Enterprise**. Every grant in this
lab is a predefined role, so the free tier would return nothing useful. That
tier is not activated, so the week demonstrates the mechanism for temporary
access and makes no claim that this estate needed it.

**Teardown** removes the entitlement, the service account and the binding. The
API enablement stays (`disable_on_destroy = false`), which costs nothing.

## What it does

Ten weeks of this lab granted roles that stay granted. This one makes a
privileged role something a principal *requests, holds briefly, and loses*,
then proves the losing half actually happens:

| | |
| --- | --- |
| Entitlement on | the platform folder |
| Grants | `roles/iam.securityReviewer` — read every IAM policy in the subtree |
| Eligible to request | a service account that holds nothing directly |
| Approver | a human, necessarily a different principal from the requester |
| Longest grant | **30 minutes** — Google's documented minimum, see below |

The test is one command run three times as the same principal: refused before,
permitted during, refused again after. The number the week owes is how long the
role binding takes to leave the folder's IAM policy once the grant expires.

## The 30-minute floor

`max_request_duration` accepts 1800s to 604800s, so **the shortest elevated
access PAM will issue is 30 minutes**. There is no way to hand someone five.
That is a constraint worth knowing before designing a workflow around it, and
it sets the floor on how long each expiry measurement takes.

## Prerequisites

- Week 01's folder hierarchy and Week 02's federated pipeline.
- A **Week 02 amendment** granting `tf-apply`
  `roles/privilegedaccessmanager.admin`. It already holds
  `roles/resourcemanager.folderAdmin`, which folder-level entitlements also
  require. An identity must not manage its own grants, so that amendment is
  hand-run, as every such amendment in this lab has been.
- `privilegedaccessmanager.googleapis.com`, which this week enables. It was
  **not** enabled as of 2026-10-28.

See [LAB.md](./LAB.md) for the full runbook.

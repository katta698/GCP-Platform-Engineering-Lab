# Figure plan — Week 12

**Goal in one sentence:** put a secret under a key we hold, then show that of
the two things Google calls "rotation" in this week's configuration, only one of
them rotates anything.

**Prerequisites:** the platform security project (Week 01), which already has
`cloudkms` and `secretmanager` enabled — this week is what those enablements
were for; the federated pipeline (Week 02); and a Week 02 amendment granting
`tf-apply` `cloudkms.admin`, `secretmanager.admin`, `pubsub.admin` and
`serviceusage.serviceUsageAdmin` on that one project, with matching viewer roles
for `tf-plan` because refresh runs as the plan identity (Week 10).

Slots are numbered in **the order a reader performs the steps**. Written before
capturing anything. Retired slots go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-repo-structure.png` | rendered card | major directories and what each is responsible for | matches the committed `.card` |
| 02 | `02-secret-rotation-and-cmek.png` | GCP console | the secret's detail page: rotation period, the Pub/Sub topic it notifies, and the customer-managed key encrypting it | both of the week's subjects visible in one view, and the **key named is ours**, not a Google-managed one |
| 03 | `03-notified-not-rotated.png` | terminal card | a `SECRET_ROTATE` message pulled off the observer subscription, with the secret's version count identical either side of it | message delivered **and** version count unchanged — the schedule published and did nothing else |
| 04 | `04-rotator-added-version.png` | terminal card | the same schedule firing with the rotator deployed, and a version 2 appearing | the count moves **only** once code we wrote is subscribed |
| 05 | `05-key-disabled-read-denied.png` | terminal card | the same identity reading the secret successfully, then refused after the key version is disabled | a denial as an identity that **holds** `secretmanager.versions.access`, with the secret's own IAM policy untouched |
| 06 | `06-key-survives-destroy.png` | terminal card | `terraform destroy` reporting success, then the key still listed in the project | Terraform's own note tested against Google's current documentation |
| 07 | `07-cost.png` | console / BigQuery | the actual charge for the week | **cost slot — exempt** from the pre-destroy check; cannot be captured until roughly a day after teardown |

## Capture order is NOT figure order

Numbered for the reader, captured by what the post cannot be published without.

**Capture 03 and 05 first.** They are the two claims; everything else is
context. 03 is perishable in a way worth naming: the message sits on the
subscription for a 24h retention window, and the "before" version count only
means something if it is read before anything is subscribed to the topic. Once
the rotator from slot 04 is deployed there is no way back to an unrotated
observation without rebuilding the week.

**02 must be captured before the teardown experiment**, for the same reason
Week 03's dry-run console state was: the page stops existing when the secret
does.

## Why these seven

**03 is the post.** The claim is that a rotation schedule rotates nothing, and
the only honest evidence is a notification that demonstrably arrived sitting
beside a version count that demonstrably did not move. Either half alone proves
nothing — an unchanged count with no message means the schedule never fired, and
a message with no count means nothing was checked.

**04 exists because 03 is a negative result.** "It doesn't work" is a complaint;
"it doesn't work, and here is what makes it work" is a finding. The pair also
rules out the dull explanation for 03, which is that rotation was simply
misconfigured.

**05 is the security evidence, and it is a denial.** CMEK is easy to assert and
hard to show. Disabling the key version — touching neither the secret nor one
IAM binding — makes the value unreadable to a caller who still holds every
permission required to read it. Attempted as an identity that genuinely holds
`secretmanager.versions.access`, because an under-privileged attempt fails
identically and proves nothing.

**06 is the cleanup finding, and it is the one that contradicts the tooling.**
Google's documentation says key rings and keys can be deleted; the Terraform
provider's own documentation says `CryptoKeys cannot be deleted from Google
Cloud Platform`. A terminal is the right surface because the evidence is an exit
code of zero next to a resource that is still there.

**A console screenshot was considered and rejected for 03, 04, 05 and 06.** The
secret's version list does show a count, but the evidence in each of those cases
is a *sequence* — a command, its exit state, then the same command again — and a
page shows one moment. 02 is a console shot precisely because it is the one
place where a single moment is the evidence: rotation and CMEK configured
together on one object.

## No figure for

- **The key ring, the topic or the subscription existing.** The Terraform run
  already proves that, and a list with one row in it shows no idea.
- **The IAM bindings**, including the service agent's grant on the key. By the
  standing test, identity objects almost never earn a figure — and this one is
  proven more strongly by slot 05, where removing the key's usefulness breaks
  the secret.
- **The HCP run.** Every week in this series has one and it carries no idea
  specific to this week. The deployment mechanism is described in prose.

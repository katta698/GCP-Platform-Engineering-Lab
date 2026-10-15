# Figure plan — Week 09

**Goal in one sentence:** find every service account in the organization, prove
which have never been used, and remove them in the reversible direction.

**Prerequisites:** an organization with service accounts that have some history
(Weeks 01–08 supply that), and Policy Intelligence enabled on the quota project.

Slots are numbered in **the order a reader performs the steps**. Written before
capturing. Retired slots go in `UNUSED.txt` with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-terraform-layout.png` | rendered card | every file, its job and line count | 3 resource blocks; `validate.sh` the longest file |
| 02 | `02-hcp-apply.png` | HCP console | the run that applied it | **Applied**, 3 resources |
| 03 | `03-service-accounts-before.png` | GCP console | the two default SAs, **enabled**, before the change | both listed, status not disabled |
| 04 | `04-service-accounts-after.png` | GCP console | the same list, both **disabled** | both show the disabled state |

## Why these four

03 and 04 are the same console view before and after, because that pair *is* the
week's result. One picture of a disabled account proves nothing; the pair proves
a change. **03 is perishable** — it cannot be recaptured once the apply runs, so
it is taken first, before anything is deployed.

01 can never be lost to a teardown, which is why every week carries it.

## What is deliberately not a figure

- **The last-authentication evidence.** `gcloud policy-intelligence
  query-activity` output — five accounts and their dates, two reading NEVER. A
  table in the post is clearer than a screenshot, and the dates are the point.
- **The key-creation constraint gap.** Two `gcloud org-policies describe` calls
  returning opposite answers for the legacy and managed generations of the same
  rule. Terminal output, quoted.
- **Nothing breaking after the disable.** The proof is Weeks 06–08 validators
  still passing, which is terminal output, not a picture.
- **Cost.** $0, and no bill to photograph.

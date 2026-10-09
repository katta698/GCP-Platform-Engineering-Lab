# Figure plan — Week 08

**Goal in one sentence:** make the read-only half of the CI pipeline genuinely
read-only, and prove it.

**Prerequisites:** an organization, HCP Terraform with Workload Identity
Federation (Week 02), and a Cloud Asset Inventory feed to protect (Week 07).

Slots are numbered in **the order a reader performs the steps**, not the order
they were captured. Written before capturing; retired slots go in `UNUSED.txt`
with a reason.

| # | File | Method | Shows | Stated check |
| --- | --- | --- | --- | --- |
| 01 | `01-terraform-layout.png` | rendered card | every file, its job and line count | 3 resource blocks in 102 lines; `validate.sh` is the longest file |
| 02 | `02-hcp-apply.png` | HCP console | the run that created them | status **Applied**, 4 resources, Terraform v1.14.8 |
| 03 | `03-custom-role.png` | GCP console | the custom role that replaced the over-grant | `tfPlanAssetReader`, **Enabled** |
| 04 | `04-deny-policy.png` | GCP console | the guardrail behind it | `deny-asset-feed-deletion` on the **Deny** tab |

## Why these four and no more

The rule is to screenshot a resource when the picture shows the week's **idea**,
not to prove the resource exists — the Terraform run already proves that. By
that test most of this week earns no figure: IAM bindings, the role swap and the
grants are all invisible as pictures.

**01 can never be lost to a teardown.** It needs no live resources, which is why
every week carries it.

**02 keeps its two errored runs in frame** rather than cropping to the successful
apply. They are the `denypolicies.create` denial and the invalid principal
format — two of the week's three findings. A clean single-apply shot would make
the build look smoother than it was.

## What is deliberately not a figure

- **The before/after access states.** Three Policy Troubleshooter calls. A table
  in the post is clearer than a photograph of a console form, and the answer
  matters rather than the act of asking.
- **The v1-vs-v3 divergence** — the week's main finding. Two JSON responses,
  quoted side by side.
- **The guardrail working.** Proving it needed `roles/cloudasset.owner`
  temporarily re-granted. That state existed for about a minute and is gone; the
  evidence is the recorded output, not a screenshot of a transient condition.
- **Cost.** $0, and there is no bill to photograph.

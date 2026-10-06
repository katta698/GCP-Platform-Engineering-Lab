# Screenshot plan — Week 08

Four images. The post is short, so each carries a step.

---

**`05-terraform-layout.png`** — the layout card, rendered by
`scripts/screenshots/render_tree_card.py` from `docs/blog/tree.txt`.

Standing requirement for every GCP lab post from Week 07 on, enforced by
`check_lab_post_shape.py` in the blog repo. Note what it shows here: 3 resource
blocks in 102 lines, and `validate.sh` is the longest file in the week — which
is the point, since a guardrail nobody tested is a guess.

**`01-hcp-apply.png`** — the HCP run, applied. The deploy step, and the standing
evidence that this ran with no Google credential on the machine that started it.

Shows `Applied`, 4 resources, and **four runs: two errored**. Those stay in
frame deliberately — they are the `denypolicies.create` denial and the invalid
principal format, which are two of the week's three findings. A cropped
single-apply shot would make the build look smoother than it was.

Captured only after Jay signed in. The session had lapsed, and the pre-apply
check now tests HCP as well as Google so that is caught before a week is built
rather than after it is written up.

**`02-custom-role.png`** — IAM & Admin → Roles → **Custom**, showing
`Terraform Plan - Asset Reader` / `tfPlanAssetReader`, Enabled.

Captured with `--click-text "Custom"`: the page opens on Predefined, which lists
hundreds of Google roles and none of ours.

**`03-deny-policy.png`** — IAM → **Deny** tab, showing `deny-asset-feed-deletion`.

The console path is `/iam-admin/iam/deny`, not `/iam-admin/denypolicies` — the
latter 404s, and the capture script refused to save it, which is the guard
working.

---

## What has no screenshot, and should not pretend to

- **The before/after access states.** Three Policy Troubleshooter calls and their
  answers. A table in the post is clearer than a picture of a console form, and
  the answer is what matters rather than the act of asking.
- **The v1-vs-v3 divergence** — the week's main finding. Two JSON responses, best
  quoted side by side.
- **The deny policy working.** Proving it needed `roles/cloudasset.owner`
  temporarily re-granted; that state existed for about a minute and is gone. The
  evidence is the recorded output, not a screenshot of a transient condition.

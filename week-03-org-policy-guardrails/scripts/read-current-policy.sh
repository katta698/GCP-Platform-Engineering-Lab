#!/usr/bin/env bash
# Read what organization policy already says, BEFORE writing any of it.
#
#   ORG_ID=... ./scripts/read-current-policy.sh
#
# This runs first, and it is not a formality. This organization did not start
# empty: every organization created on or after 3 May 2024 inherits Google's
# security baseline, already enforced, with nobody in this lab having chosen it.
# Writing a constraint that the baseline already sets is not a no-op — the
# effective policy is the one closest to the resource, so a policy written at the
# organization REPLACES the inherited spec rather than adding to it. A carelessly
# written "hardening" policy can therefore loosen what was already there.
#
# So: read the effective policy, not just the list of what is set.
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"

echo "== Policies currently SET on the organization =="
echo "   Anything listed here was set by someone or inherited from the baseline."
gcloud org-policies list --organization="$ORG_ID"
echo

echo "== The same list, with each policy's actual spec =="
echo "   list is a summary. describe is what is enforced."
gcloud org-policies list --organization="$ORG_ID" --format="value(constraint)" \
  | while read -r c; do
      echo "--- ${c}"
      gcloud org-policies describe "${c#constraints/}" \
        --organization="$ORG_ID" --format=yaml 2>&1 | sed 's/^/    /'
    done
echo

echo "== Folder-level policy, if any =="
echo "   All four of Week 01's folders. A policy set on a folder overrides the"
echo "   organization's for everything beneath it."
#
# Recursive, and that is not incidental. `folders list --organization` returns
# only DIRECT children — it reported platform and workloads and stopped, leaving
# workloads/dev and workloads/prod unexamined. Since the whole subject of this
# week is that policy inherits downward and the closest policy wins, a check that
# cannot see the deepest node is a check that would miss the override that
# matters most.
walk_folders() {
  local parent_flag="$1" indent="$2"
  gcloud resource-manager folders list "$parent_flag" \
    --format="value(name,displayName)" 2>/dev/null \
    | while read -r id name; do
        local fid="${id##*/}"
        local set_here
        set_here=$(gcloud org-policies list --folder="$fid" \
          --format="value(constraint)" 2>/dev/null || true)
        if [[ -n "$set_here" ]]; then
          echo "${indent}--- ${name} (${fid})"
          echo "$set_here" | sed "s/^/${indent}    /"
        else
          echo "${indent}--- ${name} (${fid}): none set, inherits from parent"
        fi
        walk_folders "--folder=$fid" "${indent}  "
      done
}
walk_folders "--organization=$ORG_ID" ""
echo

echo "== EFFECTIVE policy, which is not the same question =="
#
# `gcloud org-policies list` shows policies that were explicitly SET. A managed
# constraint can be enforced on this organization with no policy set on it at
# all, because managed constraints may carry a Google default — and the default
# does not appear in `list`, in `describe`, or in the count of policies.
#
# Missing this inverts the meaning of a reading. On 2026-09-03
# iam.managed.disableServiceAccountApiKeyCreation was absent from `list` and was
# therefore treated as "not set, safe to add". It was already enforced, with a
# parameter exempting the Gemini API, and only --effective said so.
#
# The console agrees with --effective, not with `list`: it reported 26 active
# organization policies where `list` returned 12.
#
# --effective is also the only place the parameter SCHEMA of a managed constraint
# is visible. The reference documentation describes what the parameterised
# constraints do without publishing their fields; the live effective policy
# prints them.
for c in $(gcloud org-policies list --organization="$ORG_ID" --show-unset             --format="value(constraint)" | grep '\.managed\.'); do
  eff=$(gcloud org-policies describe "$c" --organization="$ORG_ID" --effective         --format="value(spec.rules[0].enforce)" 2>/dev/null || true)
  set_here=$(gcloud org-policies describe "$c" --organization="$ORG_ID"         --format="value(spec.rules[0].enforce,dryRunSpec.rules[0].enforce)" 2>/dev/null || true)
  if [[ "$eff" == "True" && -z "$set_here" ]]; then
    echo "    ENFORCED BY DEFAULT, nothing set here: ${c}"
  fi
done
echo

echo "== Custom constraints already defined =="
echo "   Expect none. If any exist, the name-reuse measurement is contaminated."
gcloud org-policies list-custom-constraints --organization="$ORG_ID"
echo

echo "== Constraints available to be set =="
#
# Discovery is a FLAG on list, not a subcommand. There is no
# `gcloud org-policies list-constraints`; the v2 surface has no verb for
# enumerating constraints at all, and gcloud's "Maybe you meant" suggestion
# points at `list`, `delete` and `delete-custom-constraint` without mentioning
# --show-unset. Worth knowing before going looking for a command that is not
# there.
echo "   Total available on this organization:"
gcloud org-policies list --organization="$ORG_ID" --show-unset \
  --format="value(constraint)" | wc -l

echo "   Of those, the managed (.managed.) generation — parameters and built-in"
echo "   dry-run support, documented as a direct replacement for the legacy names:"
gcloud org-policies list --organization="$ORG_ID" --show-unset \
  --format="value(constraint)" | grep -c '\.managed\.'
echo
gcloud org-policies list --organization="$ORG_ID" --show-unset \
  --format="value(constraint)" | grep '\.managed\.' | sort | sed 's/^/    /'

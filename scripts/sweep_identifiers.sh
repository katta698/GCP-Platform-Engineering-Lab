#!/usr/bin/env bash
# Every account identifier this lab must never publish, checked in one place.
#
#   ./scripts/sweep_identifiers.sh            # whole repo
#   ./scripts/sweep_identifiers.sh week-10-*  # one week
#
# Exit 0 = clean. Exit 1 = something that must not land in git is in a file that
# would.
#
# Why this is a script
# --------------------
# The sweep used to be three greps written out in SESSION_CONTEXT.md, copied by
# hand each week. On 2026-10-23 Week 10 introduced a FOURTH identifier - the
# Cloud Identity directory customer ID - and the documented command had no way
# to know about it. Running the longer list for the first time also surfaced six
# occurrences of the super-admin address in five tracked files, committed months
# earlier, which the three-pattern version had never looked for.
#
# A sweep you retype is a sweep that drifts behind the identifiers it exists to
# catch. The patterns are derived here, never typed, so adding a new kind of
# identifier means editing one file.
#
# Every value is READ from gitignored state or from the live cloud, so this file
# contains no secret and is itself safe to commit - the failure mode of the
# original, which had the email typed into it and so matched its own
# documentation on every run.
set -uo pipefail

cd "$(dirname "$0")/.."

TFVARS="terraform/bootstrap/terraform.tfvars"
[[ -f "$TFVARS" ]] || { echo "no $TFVARS - run from a machine with the lab's local state"; exit 1; }

ORG=$(sed -n 's/^org_id *= *"\([^"]*\)".*/\1/p'          "$TFVARS")
BILL=$(sed -n 's/^billing_account *= *"\([^"]*\)".*/\1/p' "$TFVARS")
: "${ORG:?org_id not found in tfvars}"

# Derived from the cloud rather than stored: a customer ID or project number
# typed into this file would be the leak it is checking for.
CUST=$(gcloud organizations describe "$ORG" --format="value(owner.directoryCustomerId)" 2>/dev/null | tr -d '\r' || true)
# EVERY project's number, not just the seed's.
#
# This line used to name one project as a literal:
#   NUM=$(gcloud projects describe katta698-gcp-lab-seed ...)
#
# So the sweep checked the seed project's number and was blind to every other
# project in the organization. On 2026-11-05 a wider grep found the SECURITY and
# LOGGING project numbers in week-09-sa-lifecycle/README.md and its main.tf,
# committed and public since October, with the sweep reporting "clean" on every
# run in between. A check that only looks where you remembered to point it is
# not a check.
#
# Enumerated from the cloud, so a project created by a future week is covered on
# the day it exists without anyone editing this file.
#
# `tr -d` of the carriage return is LOAD-BEARING on Windows, not tidying.
# gcloud emits CRLF here, so `mapfile -t` strips the newline and KEEPS the
# carriage return - every pattern becomes "<number><CR>", which cannot match
# anything in a file. The sweep then prints a confident "ok" per number while
# searching for a string that does not exist. Found by planting a known leak and
# watching the widened sweep report clean; without that self-test, the fix for
# the first bug would have shipped looking like it worked.
mapfile -t NUMS < <(gcloud projects list --format="value(projectNumber)" 2>/dev/null | tr -d '\r' || true)

# The operator address. Masked in every screenshot by capture_gcp.py, which
# publishes service-account domains and nothing else - so prose must hold it to
# the same standard the images are held to.
#
# READ from the active gcloud config, never written here. The first version of
# this script carried it as a literal default and was flagged by its own first
# run - the identical failure its header describes two paragraphs up. Writing
# the warning down did not prevent committing the thing it warned about; the
# check did.
OPERATOR=$(gcloud config get-value account 2>/dev/null | tr -d '\r' | grep -v '^$' || true)

declare -a PATTERNS=() NAMES=()
add() { [[ -n "${2:-}" ]] && { NAMES+=("$1"); PATTERNS+=("$2"); }; }
add ORG_ID          "$ORG"
add BILLING_ACCOUNT "$BILL"
add CUSTOMER_ID     "$CUST"
# Labelled by INDEX, never by value. Interpolating the number into the label
# would print the identifier into the terminal, the CI log and the pre-push
# output on every run - publishing the thing being swept for, in the output of
# the sweep.
#
# The first version of this comment illustrated the point with a real project
# number, and the sweep immediately flagged this file. That is the failure its
# own header describes: a control that matches its own documentation. Caught by
# the very widening it was written to explain.
_i=0
for n in "${NUMS[@]:-}"; do _i=$((_i + 1)); add "PROJECT_NUMBER #${_i}" "$n"; done
add OPERATOR_EMAIL  "$OPERATOR"
add GMAIL_IDENTITY  "${PERSONAL_GMAIL:-}"

echo "Sweeping ${#PATTERNS[@]} identifier pattern(s) over files that would land in git."
echo "(--untracked honours .gitignore, so SESSION_CONTEXT.md and tfvars are correctly out of scope.)"
echo

found=0
for i in "${!PATTERNS[@]}"; do
  # -F literal, -l names only: never print the value itself, or the sweep's own
  # output becomes the thing it is trying to prevent.
  mapfile -t hits < <(git grep --untracked -F -l -e "${PATTERNS[$i]}" -- "${@:-.}" 2>/dev/null || true)
  if (( ${#hits[@]} )); then
    found=1
    echo "  FAIL ${NAMES[$i]} appears in ${#hits[@]} file(s):"
    printf '         %s\n' "${hits[@]}"
  else
    echo "  ok   ${NAMES[$i]}"
  fi
done

# ---------------------------------------------------------------------------
# The generic check, and the reason it exists
#
# Everything above compares against a LIST of identifiers someone remembered to
# add. That is exactly how both leaks found on 2026-10-23 survived for months:
# the super-admin address was never on the list, and the personal Gmail was on
# it only when an environment variable happened to be set, which it never was.
#
# capture_gcp.py already holds the correct policy for images - every address on
# a page is masked unless its domain is a service identity. This applies the same
# rule to the repo, so a NEW address nobody has thought of is caught on its first
# commit rather than on the day someone extends a list.
#
# `grp-` addresses are allowlisted, added 2026-10-24 after Week 10. The rule the
# control is actually enforcing is "no identifier belonging to a PERSON or an
# ACCOUNT", and a group alias following this lab's naming convention is neither -
# it is a role address on an already-public domain, in the same class as a
# service account. It is also already published in the Week 10 post, so masking
# it here would be theatre rather than privacy.
#
# Note the inconsistency this exposes: capture_gcp.py masks group addresses in
# screenshots, which made Week 10's folder-IAM figure show a group icon holding a
# role with the group's own address redacted - a figure partly defeating its own
# stated purpose. That file should carry the same allowlist. Not changed here
# because another session had it open; recorded so it is not forgotten.
# ---------------------------------------------------------------------------
echo
echo "Scanning for any human email address (service identities are publishable)."

mapfile -t email_hits < <(
  git grep --untracked -I -o -E "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" -- "${@:-.}" 2>/dev/null |
    grep -viE "(gserviceaccount\.com|googleapis\.com|system\.gserviceaccount\.com|noreply@|example\.(com|org)|your-domain|@domain|user@|operator@|admin@your|^[^:]*:grp-)" |
    sort -u || true
)

if (( ${#email_hits[@]} )); then
  found=1
  echo "  FAIL ${#email_hits[@]} human address occurrence(s):"
  # Print the FILE and the local part only - never the full address, or this
  # output becomes the leak.
  for h in "${email_hits[@]}"; do
    file="${h%%:*}"; addr="${h##*:}"
    printf '         %-62s %s@...
' "$file" "${addr%%@*}"
  done
else
  echo "  ok   no human addresses"
fi

echo
if (( found )); then
  echo "Do not push. Replace each occurrence with a variable or placeholder."
  exit 1
fi
echo "Clean - no account identifier appears in any file that would land in git."

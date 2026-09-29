#!/usr/bin/env bash
# Export a snapshot of the organization's hierarchy into BigQuery.
#
#   ORG_ID=... ./scripts/snapshot.sh
#
# Why this is a script and not a Terraform resource
#
# There is no google_cloud_asset_* resource for an export. A snapshot is an
# operation with a moment attached, not a thing you own: running it twice gives
# two different answers and neither is "drift". Terraform's job is to make the
# destination and the feed exist, which it does; this is the part that asks the
# question.
#
# The feed and the snapshot answer different questions and you want both:
#   feed      what CHANGED, within seconds, as a stream
#   snapshot  what IS, right now, as a table you can join and aggregate
set -euo pipefail

: "${ORG_ID:?set ORG_ID}"
DATA_PROJECT="${DATA_PROJECT:-katta698-gcp-logging}"
SEED_PROJECT="${SEED_PROJECT:-katta698-gcp-lab-seed}"
DATASET="${DATASET:-asset_inventory}"

TABLE="projects/${DATA_PROJECT}/datasets/${DATASET}/tables/hierarchy"

echo "== Exporting organization hierarchy to BigQuery =="
echo "   content-type: resource"
echo "   destination:  ${DATA_PROJECT}.${DATASET}.hierarchy"
echo
# --output-bigquery-force overwrites the table rather than appending. A
# snapshot is a picture of now; appending would silently turn the table into a
# pile of overlapping pictures with no column saying which is which.
gcloud asset export \
  --organization="$ORG_ID" \
  --content-type=resource \
  --bigquery-table="$TABLE" \
  --output-bigquery-force \
  --billing-project="$SEED_PROJECT"

echo
echo "The export is asynchronous. gcloud returns an operation name; the rows"
echo "appear when it finishes. Poll with the describe command it printed, or"
echo "just re-run the query below until it returns."

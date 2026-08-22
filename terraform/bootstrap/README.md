# Bootstrap

Runs once. Creates the seed project that anchors the lab.

**Applied 2026-08-21.** State lives in HCP Terraform, organization `Katta`,
project **GCP Platform Lab**, workspace `gcp-bootstrap`.

## What exists after this

| Resource | Value |
| --- | --- |
| Seed project | `katta698-gcp-lab-seed`, parent = organization |
| Enabled APIs | resource manager, billing, service usage, IAM, IAM credentials, storage, STS |
| GCS bucket | `katta698-gcp-lab-seed-tfstate-1f604b95` — see "The bucket" below |

## How the state ended up in HCP

The first apply ran with local state, because the original design put state in a
GCS bucket that this configuration itself creates. That was then reconsidered:
the AWS lab already runs on HCP Terraform, and one workspace list across both
clouds is worth more than a self-contained GCS backend.

So the migration went local → GCS → HCP on the same day. The GCS step is not
something a fresh run needs to repeat.

**If you ever rebuild this from scratch**, skip GCS entirely: put the `cloud {}`
block in `versions.tf` from the start and there is no chicken-and-egg at all —
HCP does not need anything in GCP to exist first. That is a genuine advantage of
HCP over a cloud-native backend, and worth a paragraph in the blog.

Migration note: HCP does **not** accept `-migrate-state` or `-force-copy`. Plain
`terraform init` detects the backend change and prompts; answer `yes` to copy the
existing state up.

## The bucket

`katta698-gcp-lab-seed-tfstate-1f604b95` no longer holds live state — HCP does.
It still contains the stale `bootstrap/default.tfstate` object from before the
migration, which is a trap for anyone reading it later and assuming it is current.

It is still managed by this configuration and carries `prevent_destroy = true`.
Decide one of:

- **Delete it.** Remove the resource from `main.tf`, drop `prevent_destroy`, apply.
  Cleanest, since it serves no purpose now.
- **Repurpose it.** Rename in intent — lab artifacts, exported billing data,
  build outputs — and delete the stale state object so nobody mistakes it for the
  real thing.

Leaving it exactly as-is is the one option to avoid: a bucket named `-tfstate-`
holding an out-of-date state file is actively misleading.

## Running it

```bash
cp terraform.tfvars.example terraform.tfvars
```

Fill in `terraform.tfvars` — org ID, billing account, project ID, bucket suffix.
It is gitignored and must stay that way.

```bash
terraform init
```

```bash
terraform plan
```

```bash
terraform apply
```

## Execution mode

The `gcp-bootstrap` workspace is set to **local execution**. Runs happen on the
workstation against Application Default Credentials; HCP stores state and history
only.

Remote execution requires GCP credentials inside HCP. The only acceptable way to
provide them is Workload Identity Federation dynamic credentials — never a
service account key pasted into a workspace variable. That setup is Week 05,
after which these workspaces flip to `remote`.

Terraform reads **ADC**, not your `gcloud auth login` session. If a plan fails
with a credentials error:

```bash
gcloud auth application-default login
```

## Cost note

Nothing here bills per hour. The project and API enablements are free, the bucket
holds kilobytes, and HCP Terraform's free tier covers this comfortably.

## Teardown

The project carries `prevent_destroy = true`. Destroying it would orphan every
later week. Removing it is a manual, deliberate act, not a `terraform destroy`.

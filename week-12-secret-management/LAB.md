# Week 12 lab guide — Secret management

How to reproduce this week from scratch. The blog post explains what it means;
this explains how to run it.

> **Status:** written against the configuration as committed, not yet executed
> end to end. Expected outputs marked *(predicted)* have not been observed and
> must be replaced with real output once the week runs. Nothing in this file is
> presented as a measurement until it is one.

## Prerequisites

| Requirement | Why | From |
| --- | --- | --- |
| A GCP organization with a folder hierarchy | the security project has to live somewhere deliberate | Week 01 |
| A project for keys and secrets, with `cloudkms` and `secretmanager` enabled | this week is what those enablements were for | Week 01 |
| HCP Terraform workspace with WIF dynamic credentials | no service account keys, ever | Week 02 |
| `tf-apply` / `tf-plan` grants on the security project | enabling an API is not holding a permission | this week, via a Week 02 amendment |

### Permissions

Granted on **one project** — `katta698-gcp-security` — not on the platform
folder. A folder grant would also reach the network hub and the logging
project, neither of which has any reason to hold a key or a secret.

`tf-apply`:

| Role | For |
| --- | --- |
| `roles/cloudkms.admin` | key ring, key, and the key's IAM policy |
| `roles/secretmanager.admin` | the secret and its versions |
| `roles/pubsub.admin` | topic, subscription, and the topic's IAM policy |
| `roles/serviceusage.serviceUsageAdmin` | enabling Pub/Sub, and creating the Secret Manager service agent (`services.generateServiceIdentity`) |

Stage 2 additionally needs `resourcemanager.projectIamAdmin`,
`iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `cloudfunctions.admin`,
`run.admin`, `eventarc.admin` and `storage.admin`.

`tf-plan` gets the viewer counterpart of each. This is not symmetry for its own
sake: `Refreshing state...` runs as the **plan** identity, so a plan identity
that cannot read a key ring makes the configuration unmanageable regardless of
what `tf-apply` holds. Learned in Week 10.

Neither identity holds `secretmanager.secretAccessor`. Terraform manages the
secret; it never consumes it. `secretmanager.viewer` reads metadata — labels,
replication, the rotation schedule, the list of versions — and not the payload.

**Two roles deserve naming as trades rather than details.**
`cloudkms.admin` carries `cryptoKeys.setIamPolicy`, so the pipeline decides who
may encrypt and decrypt with any key in the project; that is unavoidable for a
pipeline that creates CMEK keys, because the service agent's grant on the key
has to be written by something. It does *not* carry the crypto operations
themselves — `cloudkms.admin` cannot encrypt or decrypt.
`resourcemanager.projectIamAdmin` is needed only because Eventarc refuses to
create a trigger until the trigger's service account holds
`roles/eventarc.eventReceiver`, and that role has no scope narrower than the
project.

### Environment

| Tool | Version used |
| --- | --- |
| Terraform | 1.14.8 |
| `hashicorp/google` | `~> 6.0` |
| `hashicorp/google-beta` | `~> 6.0` |
| `hashicorp/random` | `~> 3.6` |
| `hashicorp/archive` | `~> 2.4` |
| Google Cloud SDK | 581.0.0 |
| Python | 3.13 (for `measure-rotation.py`) |

`google-beta` is here for exactly one resource,
`google_project_service_identity`. A CMEK secret cannot be created until the
Secret Manager service agent exists, because the agent — not the caller —
performs every encrypt and decrypt, and there is no GA Terraform resource that
creates one. The alternative is a hand-run `gcloud beta services identity
create`, which would make the configuration un-appliable from a clean slate.

## Configuration variables

In `terraform/terraform.tfvars`, which is **gitignored**. See
`terraform.tfvars.example`.

| Variable | Default | Notes |
| --- | --- | --- |
| `security_project_id` | — | required |
| `next_rotation_time` | — | required, RFC3339, **more than five minutes in the future** |
| `key_location` | `global` | must be `global` — see below |
| `rotation_period` | `3600s` | Google's documented minimum: *"can't be less than one hour long"* |
| `kms_rotation_period` | `7776000s` | minimum is *"greater than a day (ie, 86400)"*, so 24h exactly is rejected |
| `destroy_scheduled_duration` | `86400s` | **not** the 30-day default; see the cost note |
| `deploy_rotator` | `false` | the staging is the experiment |

**`key_location` must be `global`, and this is a constraint rather than a
choice.** A secret using automatic replication can only be encrypted with a key
in the `global` multi-region. A regional key requires user-managed replication
with one key per replica location — which is also why Cloud EKM cannot be used
with automatic replication at all: EKM keys have no global location.

**`next_rotation_time` is a variable rather than a `timestamp()` expression** on
purpose. A computed timestamp changes on every plan, so the secret would show a
permanent diff and "no changes" would stop meaning anything.

## Deployment

### 1. Grant the pipeline what it needs

The grants live in Week 02's configuration — the human-run layer that defines
who CI is — and are applied by hand from there. Week 02 runs **local**
execution permanently and by design: for `tf-apply` to apply Week 02 it would
need to manage its own grants.

```bash
cd week-02-keyless-ci/terraform
terraform init -input=false
terraform plan -input=false        # expect: adds only google_project_iam_member
terraform apply -input=false
```

Expect 8 adds for stage 1 and 14 more for stage 2, 0 changed, 0 destroyed. A
plan that proposes to change or destroy anything is a signal to stop and read
it.

### 2. Create the workspace through the API

```bash
python ../../scripts/hcp_workspace.py --name gcp-week-12
```

**Not `terraform init`.** That creates a missing workspace in HCP's *Default
Project*, which also makes the execution-mode radio button appear not to work:
the workspace inherits Default Project's `remote` with
`setting-overwrites.execution-mode = false`, so setting it in the UI does not
stick until that inheritance is broken.

### 3. Set the notification time and apply stage 1

```bash
cd week-12-secret-management
./scripts/set-next-rotation.sh 8        # 8 minutes out
cd terraform
terraform init -input=false
terraform apply -input=false
```

The script refuses anything under 6 minutes, because Secret Manager rejects a
`next_rotation_time` less than five minutes in the future and an apply takes
time of its own.

Expect 10 resources added *(predicted)*.

### 4. Validate

```bash
./scripts/validate.sh
```

Reads the cloud, never Terraform state — a successful apply is not evidence the
thing works. Exits non-zero on any failure; the exit code is the result.

## Validation procedures

### The central measurement — run this before anything else

```bash
python scripts/measure-rotation.py \
  --until 2026-11-04T21:05:00Z \
  --json docs/rotation-measurement-1.json
```

Records the version count and newest enabled version before the notification,
pulls the `SECRET_ROTATE` message off the observer subscription when it
arrives, waits 60s so that "unchanged" cannot mean "too early", and reads the
count again.

Expected, and the whole point: **notification delivered, secret unchanged**
*(predicted)*.

> **This measurement is perishable.** It only means something while nothing is
> subscribed to the topic. Once stage 2 is applied there is no route back
> without rebuilding the week. Capture figure 03 here.

If no message arrives within the grace window the script says so and exits 1.
That is a **failed measurement, not a finding** — do not write it up as one.

**On the delivery lag.** The script reports how long after the scheduled time
the message was observed. Treat that as bounded, not precise: `gcloud pubsub
subscriptions pull` does not ack, but a pulled message is invisible for the
subscription's ack deadline (60s here), so the observation is bounded below by
the poll interval and above by the ack deadline. Week 03 published an n=1 lag
as a precise figure and Week 11 had to correct the habit by publishing a range.
What this script measures precisely is whether the secret changed.

### The CMEK denial

```bash
./scripts/cmek-killswitch.sh
```

1. Confirms the caller **can** read the secret first. If it cannot, the script
   aborts — a denial measured from an identity that lacks the permission proves
   nothing, and looks identical to the control working.
2. Disables the key version. Not the secret, not an IAM binding.
3. Waits 30s, reads again, and records the failure verbatim.
4. Re-enables the version **in a `trap`**, so a crash midway cannot leave the
   secret dark. Week 03 learned this the hard way: a measurement script crashed
   having already degraded a control and left the organization in a state the
   published post contradicted.

Expected: read succeeds, then fails, then succeeds again *(predicted)*. If the
read succeeds with the key disabled, the week's CMEK claim is wrong as written
and the post gets corrected rather than the test retried.

### The rotator

```bash
./scripts/set-next-rotation.sh 8
cd terraform && terraform apply -var deploy_rotator=true
python ../scripts/measure-rotation.py --until <new time> \
  --json ../docs/rotation-measurement-2.json
```

Expected: the version count **moves** this time *(predicted)*. That is what
makes the first measurement a finding rather than a complaint — and it rules out
the dull explanation, which is that rotation was simply misconfigured.

The function filters on `eventType == "SECRET_ROTATE"`. This is not defensive
coding. The topic also carries `SECRET_VERSION_ADD`, which the rotator itself
causes, so a rotator that acts on every message rotates in an infinite loop.

## Cleanup and verification

```bash
python ../scripts/check_figures_before_destroy.py week-12-secret-management
./scripts/teardown-kms.sh --stage report      # what exists now
cd terraform && terraform destroy
cd .. && ./scripts/teardown-kms.sh --stage report   # what survived it
```

**Do not destroy on a non-zero exit from the figure check.** Teardown is the
only irreversible step in a week; every uncaptured figure becomes permanently
uncapturable the moment it applies.

### The key will survive `terraform destroy`, and the exit code will be zero

The provider says so itself:

> CryptoKeys cannot be deleted from Google Cloud Platform. Destroying a
> Terraform-managed CryptoKey will remove it from state and delete all
> CryptoKeyVersions, rendering the key unusable, but *will not delete the
> resource from the project.*

Meanwhile Google's current documentation says *"You can delete key rings, keys,
and key versions in some circumstances"*. Resolving that is what
`teardown-kms.sh` is for:

```bash
./scripts/teardown-kms.sh --stage destroy-versions   # removes rotation, schedules versions
# wait out destroyScheduledDuration (24h here, 30 days by default)
./scripts/teardown-kms.sh --stage delete             # attempt key, then key ring
```

Google's documented preconditions, which the stages follow:

1. every key version must be `DESTROYED` — not merely scheduled
2. the key must have **no automatic rotation scheduled**
3. the key must not have been created by Autokey
4. then the key can be deleted
5. once every key is gone, the key ring can be deleted

Condition 2 is the one that surprises: Terraform cannot express the *absence* of
a rotation schedule on a key it is deleting, so removing it is a deliberate
out-of-band step.

Attempting `--stage delete` early is itself a result — it shows the
precondition being enforced — so the script reports the refusal and does not
retry.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Secret fails to create with a permission error on the key, naming an account that does not exist | the Secret Manager service agent had not been created yet | `google_project_service_identity` must apply first; it is a `depends_on` edge, not a timing hope |
| Secret fails to create and the error is about the **topic** | Secret Manager validates at creation that it can publish to every configured topic, so a missing publisher binding surfaces as a secret that will not exist | the `pubsub.publisher` grant to the service agent is a `depends_on` of the secret |
| `next_rotation_time` rejected | less than five minutes in the future at apply time | `set-next-rotation.sh` with a larger number |
| `kms_rotation_period` rejected at 86400s | the minimum is *greater than* a day, not equal to it | use more than 86400s |
| CMEK rejected on a regional key | automatic replication requires a key in `global` | `key_location = "global"`, or switch to user-managed replication with a key per location |
| Rotation fires repeatedly, versions pile up | the rotator is acting on `SECRET_VERSION_ADD`, which it causes itself | filter on `eventType == "SECRET_ROTATE"` |
| A plan passes and the apply fails at token exchange | a plan over empty state never authenticates | check the workspace's workload identity provider before trusting a clean plan (Week 11) |
| `terraform destroy` succeeds and the key is still there | expected — see above | `teardown-kms.sh`, staged |

## Known limitations and production considerations

- **The rotator adds a version; it does not rotate a credential.** A real
  rotator has to change the password at the database that owns it, overlap old
  and new so in-flight consumers are not cut off, and be idempotent because
  Secret Manager retries a notification for up to seven days. All three are the
  hard part, and this lab implements none of them. Named rather than skipped:
  the gap between "adds a version" and "rotates a credential" is where the
  engineering lives.
- **The rotator disables the previous version immediately**, which is wrong for
  anything real. Production needs an overlap window.
- **`SOFTWARE` protection, not HSM.** A software version is $0.06/month against
  $1.00–$2.50 for HSM and $3,500/month for a single-tenant HSM. The control
  being demonstrated — who *holds* the key — is identical either way; hardware
  custody is a different claim and this lab does not make it.
- **No `prevent_destroy` on the key.** Every other lab would set it, and for a
  key holding real data that is right. Here the teardown *is* the experiment,
  and the secret is a generated value used by nothing.
- **Nothing consumes the secret.** A workload reading it would add a second
  thing to debug and prove nothing extra about the control.
- **One approver, one requester, one operator.** The lab has a single human.
- **Rotation at one hour** is Google's floor, not a recommendation. A real
  database credential rotating hourly would be an availability risk, not a
  security win.

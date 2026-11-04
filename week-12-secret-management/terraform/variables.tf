variable "security_project_id" {
  description = <<-EOT
    The platform security project, created in Week 01 with `cloudkms` and
    `secretmanager` already enabled - this week is what those enablements were
    for.

    Keys and secrets go here rather than in the project that consumes them, so
    that destroying a workload cannot destroy the key its data was encrypted
    with. That separation is the entire reason the folder has a security project.
  EOT
  type        = string
}

variable "region" {
  description = "Region for the Pub/Sub subscription and, later, the rotator. NOT where the key lives - see key_location."
  type        = string
  default     = "us-central1"
}

variable "key_location" {
  description = <<-EOT
    Cloud KMS location for the key ring. Must be `global`.

    Not a preference. A secret using AUTOMATIC replication can only be
    encrypted with a key in the `global` multi-region; a regional key requires
    the secret to use USER-MANAGED replication with one key per replica
    location. Google documents this as a hard requirement, and it is also why
    Cloud EKM cannot be used with automatic replication at all - EKM keys have
    no global location.
  EOT
  type        = string
  default     = "global"
}

variable "rotation_period" {
  description = <<-EOT
    Secret Manager rotation period, in seconds.

    Set to Google's documented MINIMUM: "The rotation_period can't be less than
    one hour long." So one hour is the shortest notification interval Secret
    Manager will accept, and that floor is a finding of this week rather than a
    configuration choice.

    Note what this period does NOT do. It does not rotate the secret. See the
    comment on the secret resource in main.tf.
  EOT
  type        = string
  default     = "3600s"
}

variable "next_rotation_time" {
  description = <<-EOT
    RFC3339 timestamp of the next rotation notification.

    Required whenever `rotation_period` is set, and "can't be set to less than
    five minutes in the future."

    A variable rather than a computed `timestamp()` expression on purpose: a
    computed value would change on every plan and show a permanent diff. It is
    also the lever the experiment turns - re-applying with a new value a few
    minutes out produces another notification on demand, instead of waiting a
    full hour for the schedule to come round.
  EOT
  type        = string
}

variable "kms_rotation_period" {
  description = <<-EOT
    Cloud KMS automatic rotation period, in seconds. Minimum is "greater than a
    day (ie, 86400)" - so 24h exactly is rejected and 90 days is the
    conventional choice.

    This is the OTHER rotation in this week, and the contrast is the point.
    When this period elapses Cloud KMS generates a new CryptoKeyVersion and
    makes it primary, with no code written by anyone. When Secret Manager's
    period elapses it publishes a message. Both are called rotation, in the same
    console, in the same project.

    It also has a teardown consequence: Google's own preconditions for deleting
    a key include "the key doesn't have automatic key rotation scheduled".
  EOT
  type        = string
  default     = "7776000s"
}

variable "destroy_scheduled_duration" {
  description = <<-EOT
    How long a destroyed key version sits in DESTROY_SCHEDULED before it
    actually becomes DESTROYED. Default if unset is 30 DAYS.

    Set to 24h here because a key version in DESTROY_SCHEDULED is still a
    BILLED key version - Google counts a version as active if it is "Enabled,
    Disabled, or Scheduled for destruction". Taking the default would leave this
    week metering for a month after its teardown reported success.

    This is the lab's cost rule ("cleanup.sh must actually destroy everything
    the week created") meeting a service that will not let it.
  EOT
  type        = string
  default     = "86400s"
}

variable "deploy_rotator" {
  description = <<-EOT
    Whether to deploy the rotator function.

    Not a feature flag - it is the experiment, and it has to be staged.

    The claim this week rests on is that a rotation schedule rotates nothing by
    itself. Demonstrating that requires one notification to fire with NO
    subscriber acting on it, so the secret's version count can be shown
    unchanged. Only then does deploying the rotator and firing a second
    notification prove the complement: that the version moves when, and only
    when, code you wrote moves it.

    Apply once with false, observe, then apply with true.
  EOT
  type        = bool
  default     = false
}

# Folder IDs are not secrets, but they embed the hierarchy's numbering and are
# read on screen and screenshotted for the write-up. Marked sensitive to keep
# them out of the run log; `terraform output -raw` still prints one on demand.

output "dev_folder" {
  description = "The folder the serial-console exception is written on. Resolved by display name at plan time, never carried in tfvars."
  value       = local.dev_folder
  sensitive   = true
}

output "enforcement_state" {
  description = <<-EOT
    Every constraint this week manages, and whether it is enforced or still in
    dry run. This is the week's actual status line: a constraint in dry run is
    logging violations and denying nothing, which is indistinguishable from
    enforcement in the console's summary view and completely different in effect.
  EOT
  value = merge(
    {
      for k in keys(local.boolean_constraints) :
      k => lookup(var.enforce, k, false) ? "ENFORCED" : "dry-run"
    },
    {
      (google_org_policy_custom_constraint.bucket_labels.name) = (
        lookup(var.enforce, "custom.requireTerraformLabelsOnBuckets", false) ? "ENFORCED" : "dry-run"
      )
    },
  )
}

output "custom_constraint_name" {
  description = "Full resource name of the custom constraint. Needed for the name-reuse measurement, which deletes it and attempts to recreate it under the same name."
  value       = google_org_policy_custom_constraint.bucket_labels.name
}

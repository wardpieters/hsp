mock_provider "system" {}
variables {
  kind          = "pihole"
  config_json   = "{\"proxy_address\":\"10.77.0.2\"}"
  change_tokens = ["original-wildcard-generation"]
}
run "initial" {
  command = apply
}
run "file_only_drift_repair" {
  command = apply
  variables { change_tokens = ["repaired-wildcard-generation"] }
  assert {
    condition     = output.reload_generation != run.initial.reload_generation
    error_message = "File-only drift repair must create a new reload generation even when config/unit/helper content is unchanged."
  }
  assert {
    condition     = contains(system_service_systemd.this.reload_on, output.reload_generation)
    error_message = "The service must reload the new generation."
  }
}
run "converged" {
  command = apply
  variables { change_tokens = ["repaired-wildcard-generation"] }
  assert {
    condition     = output.reload_generation == run.file_only_drift_repair.reload_generation
    error_message = "A converged configuration must not perpetually reload."
  }
}

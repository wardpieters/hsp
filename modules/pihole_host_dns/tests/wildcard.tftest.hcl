mock_provider "system" {}
variables { proxy_address = "10.77.0.2" }

run "initial" {
  command = apply
  assert {
    condition     = strcontains(system_file.wildcard.content, "address=/home.ward.nl/10.77.0.2\n") && system_service_systemd.ftl.name == "pihole-FTL" && system_service_systemd.ftl.status == "started"
    error_message = "The dedicated wildcard file must target the proxy and be connected to the existing FTL service."
  }
}
run "file_repair" {
  command = apply
  plan_options { replace = [system_file.wildcard] }
  assert {
    condition     = terraform_data.revision.id != run.initial.generation && contains(system_service_systemd.ftl.restart_on, terraform_data.revision.id)
    error_message = "Repairing the wildcard file must restart FTL even when desired content is unchanged."
  }
}
run "target_change" {
  command = apply
  variables { proxy_address = "10.77.0.6" }
  assert {
    condition     = terraform_data.revision.id != run.file_repair.generation && strcontains(system_file.wildcard.content, "address=/home.ward.nl/10.77.0.6\n")
    error_message = "A new wildcard target must update the file and service generation."
  }
}
run "converged" {
  command = apply
  variables { proxy_address = "10.77.0.6" }
  assert {
    condition     = terraform_data.revision.id == run.target_change.generation
    error_message = "Converged DNS must not perpetually restart."
  }
}

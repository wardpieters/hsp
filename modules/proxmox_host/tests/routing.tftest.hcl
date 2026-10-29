mock_provider "system" {}
variables { platform_cidr = "10.77.0.0/24" }

run "persistent_routing" {
  command = apply
  assert {
    condition = (
      strcontains(system_file.routing_unit.content, "ExecStart=/usr/sbin/sysctl -w net.ipv4.ip_forward=1") &&
      strcontains(system_file.routing_unit.content, "ExecStart=/usr/sbin/ip -4 route replace blackhole 10.77.0.0/24 metric 42760") &&
      strcontains(system_file.routing_unit.content, "ExecStop=-/usr/sbin/ip -4 route del blackhole 10.77.0.0/24 metric 42760") &&
      strcontains(system_file.startup_guard.content, "Wants=${system_service_systemd.routing.name}.service pve-firewall.service") &&
      !strcontains(system_file.startup_guard.content, "Requires=") &&
      strcontains(system_file.startup_guard.content, "ExecStartPre=/usr/bin/systemctl is-active --quiet ${system_service_systemd.routing.name}.service") &&
      strcontains(system_file.startup_guard.content, "ExecStartPre=/usr/bin/systemctl is-active --quiet pve-firewall.service") &&
      system_service_systemd.routing.enabled && system_service_systemd.routing.status == "started"
    )
    error_message = "Routing must persist and gate guest autostart without propagating a routing stop into Proxmox's stop-all-guests action."
  }
}
run "unit_repair" {
  command = apply
  plan_options { replace = [system_file.routing_unit] }
  assert {
    condition     = terraform_data.revision.id != run.persistent_routing.generation && contains(system_service_systemd.routing.reload_on, terraform_data.revision.id)
    error_message = "Repairing a managed unit must reload routing even if desired content has not changed."
  }
}
run "converged" {
  command = apply
  assert {
    condition     = terraform_data.revision.id == run.unit_repair.generation
    error_message = "Converged routing must not perpetually reload."
  }
}
run "reject_public_range" {
  command = plan
  variables { platform_cidr = "8.8.8.0/24" }
  expect_failures = [var.platform_cidr]
}
run "reject_noncanonical_range" {
  command = plan
  variables { platform_cidr = "10.77.0.1/24" }
  expect_failures = [var.platform_cidr]
}

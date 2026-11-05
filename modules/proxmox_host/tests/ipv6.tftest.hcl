mock_provider "system" {}
variables {
  platform_cidr = "10.77.0.0/24"

  he_ipv6 = {
    server_ipv4 = "216.66.84.46", local_ipv4 = "192.168.100.10", client_ipv6 = "2001:470:1f14:4d4::2/64", server_ipv6 = "2001:470:1f14:4d4::1", routed_prefix = "2001:470:1f15:4d6::/64", ula_prefix = "fd42:77:1::/48", mtu = 1480
  }

}
run "off" {
  command = plan
  variables { he_ipv6 = null }
  assert {
    condition     = length(system_file.he_helper) == 0 && output.he_ipv6_status == null
    error_message = "Default-off must create no HE host resources."
  }
}
run "enabled" {
  command = apply
  assert {
    condition     = output.he_ipv6_status.public_address == "2001:470:1f15:4d6::2" && output.he_ipv6_status.vip_interface == "hsp-vip6" && system_service_systemd.he_ipv6[0].enabled && system_service_systemd.he_ipv6[0].status == "started"
    error_message = "HE must start a persistent guarded tunnel and host-owned public /128."
  }
}
run "repair" {
  command = apply
  plan_options { replace = [system_file.he_helper[0]] }
  assert {
    condition     = terraform_data.he_revision[0].id != run.enabled.he_ipv6_generation
    error_message = "Repairing the helper must trigger reconciliation."
  }
}
run "converged" {
  command = apply
  assert {
    condition     = terraform_data.he_revision[0].id == run.repair.he_ipv6_generation
    error_message = "Unchanged HE must not reload perpetually."
  }
}
run "disable" {
  command = apply
  variables { he_ipv6 = null }
  assert {
    condition     = length(system_file.he_helper) == 0 && output.he_ipv6_status == null && system_service_systemd.routing.enabled
    error_message = "Disable must remove only HE and retain IPv4 routing."
  }
}

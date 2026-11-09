# Host-config consumes only the tunnel settings; guest derivation lives in home.
override_module { target = module.proxmox.module.he_teardown }
mock_provider "system" {}
variables {
  proxmox_ssh   = { host = "192.0.2.10", user = "root" }
  platform_cidr = "10.77.0.0/24"
  he_ipv6       = { enabled = true, server_ipv4 = "216.66.84.46", local_ipv4 = "192.168.100.10", client_ipv6 = "2001:470:1f14:4d4::2/64", server_ipv6 = "2001:470:1f14:4d4::1", routed_prefix = "2001:470:1f15:4d6::/64", ula_prefix = "fd42:77:1::/48" }
}
run "tunnel_without_manual_forwarding" {
  command = plan
  assert {
    condition     = output.he_ipv6_status.public_address == "2001:470:1f15:4d6::2"
    error_message = "Tunnel setup must work without guest forwarding or hairpin inputs."
  }
}

mock_provider "system" {}
override_module { target = module.teardown }
variables {
  public_address   = "2001:470:1f15:4d6::2"
  ula_prefix       = "fd42:77:1::/48"
  proxmox_ssh      = { host = "192.0.2.10", user = "root" }
  firewall_bridges = { fwbr1015i0 = "fd42:77:1:f::2" }
  egress           = { kuma = { address = "fd42:77:1:f::2", vnet_id = "hsp1015", ports = [{ protocol = "icmp" }, { protocol = "tcp", port = 443 }] } }
}
run "separate_owned_bridge_conntrack_before_tracking" {
  command = plan
  assert {
    condition     = strcontains(system_file.ingress_rules.content, "type filter hook prerouting priority -300") && strcontains(system_file.ingress_rules.content, "iifname \"fwbr1015i0\" ct zone set 1") && !strcontains(system_file.ingress_rules.content, "iifname \"fwbr*\" ct zone set")
    error_message = "Only participating legacy firewall bridges need a separate pre-conntrack zone; routed NAT remains in zone 0."
  }
}
run "reject_unscoped_bridge" {
  command = plan
  variables { firewall_bridges = { "fwbr*" = "fd42:77:1:f::2" } }
  expect_failures = [var.firewall_bridges]
}

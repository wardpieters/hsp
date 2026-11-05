mock_provider "proxmox" {}
variables {
  platform_cidr = "10.77.0.0/24"
  slot          = 2
  zone_id       = "hsp"
  vnet_id       = "hsp1002"
}
run "off" {
  command = plan
  assert {
    condition     = output.ipv6 == null && length(proxmox_sdn_subnet.ipv6) == 0
    error_message = "IPv4-only guests must not acquire an IPv6 subnet."
  }
}
run "ula" {
  command = plan
  variables { ipv6_cidr = "fd42:77:1:2::/64" }
  assert {
    condition     = output.ipv6.address == "fd42:77:1:2::2" && output.ipv6.gateway == "fd42:77:1:2::1" && output.address == "10.77.0.10" && !proxmox_sdn_subnet.ipv6[0].snat && proxmox_sdn_subnet.this.snat
    error_message = "ULA must use offsets 1/2 without native SNAT or IPv4 changes."
  }
}
run "reject_global" {
  command = plan
  variables { ipv6_cidr = "2001:db8::/64" }
  expect_failures = [var.ipv6_cidr]
}
run "reject_noncanonical" {
  command = plan
  variables { ipv6_cidr = "fd42:77:1:2::1/64" }
  expect_failures = [var.ipv6_cidr]
}
run "reject_wrong_size" {
  command = plan
  variables { ipv6_cidr = "fd42:77:1:2::/80" }
  expect_failures = [var.ipv6_cidr]
}

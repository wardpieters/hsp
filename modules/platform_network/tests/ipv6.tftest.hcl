mock_provider "proxmox" {}
variables {
  platform_cidr   = "10.77.0.0/24"
  protected_cidrs = ["192.168.1.0/24"]
  node_name       = "pve"
  networks        = { proxy = { slot = 2, vnet_id = "hsp1002", ipv6_cidr = "fd42:77:1:2::/64" }, mail = { slot = 16, vnet_id = "hsp1016", ipv6_cidr = "fd42:77:1:10::/64" }, other = { slot = 1, vnet_id = "hsp1001" } }
}
run "original" {
  command = apply
  assert {
    condition     = output.networks["proxy"].ipv6.address == "fd42:77:1:2::2" && output.networks["mail"].ipv6.address == "fd42:77:1:10::2" && output.networks["other"].ipv6 == null
    error_message = "Only participants receive independent ULA networks at stable slots."
  }
}
run "repair" {
  command = apply
  plan_options { replace = [module.guest["proxy"].proxmox_sdn_subnet.ipv6[0]] }
  assert {
    condition     = output.apply_generation != run.original.apply_generation
    error_message = "IPv6 subnet repair must trigger centralized apply."
  }
}
run "converged" {
  command = apply
  assert {
    condition     = output.apply_generation == run.repair.apply_generation
    error_message = "Unchanged IPv6 must converge."
  }
}
run "remove_ipv6_only" {
  command = apply
  variables { networks = { proxy = { slot = 2, vnet_id = "hsp1002" }, mail = { slot = 16, vnet_id = "hsp1016" }, other = { slot = 1, vnet_id = "hsp1001" } } }
  assert {
    condition     = output.networks["proxy"].ipv6 == null && output.networks["proxy"].address == "10.77.0.10" && output.apply_generation != run.converged.apply_generation
    error_message = "Removing IPv6 must apply SDN without removing the guest's IPv4 network."
  }
}
run "reject_duplicate_prefix" {
  command = plan
  variables { networks = { proxy = { slot = 2, vnet_id = "hsp1002", ipv6_cidr = "fd42:77:1:2::/64" }, mail = { slot = 16, vnet_id = "hsp1016", ipv6_cidr = "fd42:77:1:2::/64" } } }
  expect_failures = [var.networks]
}

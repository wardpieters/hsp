mock_provider "system" {}
override_module { target = module.teardown }
variables {
  public_address = "2001:470:1f15:4d6::2"
  ula_prefix     = "fd42:77:1::/48"
  proxmox_ssh    = { host = "192.0.2.10", user = "root" }
  forwards       = { https = { guest = "proxy", port = 443, address = "fd42:77:1:2::2", vnet_id = "hsp1002" } }
  hairpin = {
    "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 }
    "proxy/https" = { source_guest = "proxy", source_address = "fd42:77:1:2::2", source_vnet_id = "hsp1002", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 }
  }
}
run "cross_and_self_hairpin" {
  command = plan

  assert {
    condition = (strcontains(system_file.ingress_rules.content, "iifname \"hsp1001\" ip6 saddr fd42:77:1:1::2 ip6 daddr 2001:470:1f15:4d6::2 tcp dport 443 dnat to fd42:77:1:2::2") &&
      strcontains(system_file.ingress_rules.content, "oifname \"hsp1002\" ct direction original ct status dnat ct original ip6 saddr fd42:77:1:1::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ip6 saddr fd42:77:1:1::2 ip6 daddr fd42:77:1:2::2 tcp dport 443 snat to fd42:77:1:2::1") &&
      strcontains(system_file.ingress_rules.content, "iifname \"hsp1001\" oifname \"hsp1002\" ct direction original ct status dnat ct original ip6 saddr fd42:77:1:1::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ip6 saddr fd42:77:1:1::2 ip6 daddr fd42:77:1:2::2 tcp dport 443 ct state { new, established } accept") &&
      strcontains(system_file.ingress_rules.content, "iifname \"hsp1002\" oifname \"hsp1001\" ct direction reply ct status dnat ct original ip6 saddr fd42:77:1:1::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ct status snat ct reply ip6 daddr fd42:77:1:2::1 ip6 saddr fd42:77:1:2::2 ip6 daddr fd42:77:1:1::2 tcp sport 443 ct state established accept") &&
      strcontains(system_file.ingress_rules.content, "iifname \"hsp1002\" ip6 saddr fd42:77:1:2::2 ip6 daddr 2001:470:1f15:4d6::2 tcp dport 443 dnat to fd42:77:1:2::2") &&
      strcontains(system_file.ingress_rules.content, "oifname \"hsp1002\" ct direction original ct status dnat ct original ip6 saddr fd42:77:1:2::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ip6 saddr fd42:77:1:2::2 ip6 daddr fd42:77:1:2::2 tcp dport 443 snat to fd42:77:1:2::1") &&
      strcontains(system_file.ingress_rules.content, "iifname \"hsp1002\" oifname \"hsp1002\" ct direction original ct status dnat ct original ip6 saddr fd42:77:1:2::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ip6 saddr fd42:77:1:2::2 ip6 daddr fd42:77:1:2::2 tcp dport 443 ct state { new, established } accept") &&
      strcontains(system_file.ingress_rules.content, "iifname \"hsp1002\" oifname \"hsp1002\" ct direction reply ct status dnat ct original ip6 saddr fd42:77:1:2::2 ct original ip6 daddr 2001:470:1f15:4d6::2 ct original protocol 6 ct original proto-dst 443 ct reply ip6 saddr fd42:77:1:2::2 ct status snat ct reply ip6 daddr fd42:77:1:2::1 ip6 saddr fd42:77:1:2::2 ip6 daddr fd42:77:1:2::2 tcp sport 443 ct state established accept") &&
      !strcontains(system_file.ingress_rules.content, "hook output") &&
      !strcontains(system_file.ingress_rules.content, "masquerade") &&
      !strcontains(system_file.ingress_rules.content, "snat to fd42:77:1:2::1:") &&
      !strcontains(system_file.ingress_rules.content, "ct state established accept\n    ct status dnat") &&
      length([for row in split("\n", system_file.ingress_permissions.content) : row if row == "P|2001:470:1f15:4d6::2|fd42:77:1:1::2|tcp|443|hsp1001|fd42:77:1:2::2|hsp1002|fd42:77:1:2::1"]) == 1 && length([for row in split("\n", system_file.ingress_permissions.content) : row if row == "P|2001:470:1f15:4d6::2|fd42:77:1:2::2|tcp|443|hsp1002|fd42:77:1:2::2|hsp1002|fd42:77:1:2::1"]) == 1
    )
    error_message = "cross_and_self_hairpin contract failed."
  }
}
run "empty_hairpin" {
  command = plan
  variables { hairpin = {} }
  assert {
    condition     = !strcontains(system_file.ingress_permissions.content, "P|")
    error_message = "empty_hairpin contract failed."
  }
}
run "reject_unknown_forward" {
  command = plan
  variables { hairpin = { "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "absent", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 } } }
  expect_failures = [var.hairpin]
}
run "reject_mismatched_target" {
  command = plan
  variables { hairpin = { "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "other", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 } } }
  expect_failures = [var.hairpin]
}
run "reject_wrong_gateway" {
  command = plan
  variables { hairpin = { "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:1::1", port = 443 } } }
  expect_failures = [var.hairpin]
}
run "reject_invalid_source" {
  command = plan
  variables { hairpin = { "cloud/https" = { source_guest = "cloud", source_address = "2001:db8::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 } } }
  expect_failures = [var.hairpin]
}
run "reject_mismatched_composite_key" {
  command = plan
  variables { hairpin = { "cloud/https" = { source_guest = "other", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", port = 443 } } }
  expect_failures = [var.hairpin]
}
run "hairpin_only_source_bridge" {
  command = plan
  variables { firewall_bridges = { fwbr1001i0 = "fd42:77:1:1::2" } }
  assert {
    condition     = strcontains(system_file.ingress_rules.content, "iifname \"fwbr1001i0\" ct zone set 1")
    error_message = "hairpin_only_source_bridge contract failed."
  }
}
run "he_accepts_are_path_scoped" {
  command = plan

  assert {
    condition     = strcontains(system_file.ingress_rules.content, "iifname \"hsp-he6\" oifname \"hsp1002\" ct direction original ct status dnat")
    error_message = "he_accepts_are_path_scoped contract failed."
  }
}
run "hairpin_errors_precede_protected_denials" {
  command = plan

  assert {
    condition     = strcontains(split("iifname \"hsp-he6\" ip6 saddr", system_file.ingress_rules.content)[0], "ct original ip6 saddr fd42:77:1:1::2 ct original ip6 daddr 2001:470:1f15:4d6::2")
    error_message = "hairpin_errors_precede_protected_denials contract failed."
  }
}

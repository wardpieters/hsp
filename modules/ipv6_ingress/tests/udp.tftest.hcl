mock_provider "system" {}
override_module { target = module.teardown }
variables {
  public_address = "2001:470:1f15:4d6::2"
  ula_prefix     = "fd42:77:1::/48"
  proxmox_ssh    = { host = "192.0.2.10", user = "root" }
  egress         = { cloud = { address = "fd42:77:1:1::2", vnet_id = "hsp1001", ports = [{ protocol = "udp", port = 443 }, { protocol = "udp", port = 123 }, { protocol = "icmp" }] } }
  forwards       = { https = { guest = "proxy", protocol = "udp", port = 443, address = "fd42:77:1:2::2", vnet_id = "hsp1002" } }
  hairpin = {
    "other/https" = { source_guest = "other", source_address = "fd42:77:1:3::2", source_vnet_id = "hsp1003", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", protocol = "udp", port = 443 }
    "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", protocol = "udp", port = 443 }
    "proxy/https" = { source_guest = "proxy", source_address = "fd42:77:1:2::2", source_vnet_id = "hsp1002", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:2::2", target_vnet_id = "hsp1002", target_gateway = "fd42:77:1:2::1", protocol = "udp", port = 443 }
  }
}
run "enabled" {
  command = apply
  assert {
    condition     = strcontains(system_file.ingress_rules.content, "udp dport 443 dnat to fd42:77:1:2::2") && strcontains(system_file.ingress_rules.content, "ct original protocol 17 ct original proto-dst 443") && strcontains(system_file.ingress_permissions.content, "|udp|443|")
    error_message = "UDP public and hairpin forwards must render UDP NAT, guards and permission records."
  }
}
run "revoked" {
  command = apply
  variables { hairpin = {} }
}
run "same_number_different_protocol" {
  command = plan
  variables {
    hairpin = {}
    forwards = {
      tcp = { guest = "proxy", protocol = "tcp", port = 443, address = "fd42:77:1:2::2", vnet_id = "hsp1002" }
      udp = { guest = "other", protocol = "udp", port = 443, address = "fd42:77:1:3::2", vnet_id = "hsp1003" }
    }
  }
}
run "reject_invalid_protocol" {
  command = plan
  variables {
    hairpin  = {}
    forwards = { invalid = { guest = "proxy", protocol = "icmp", port = 443, address = "fd42:77:1:2::2", vnet_id = "hsp1002" } }
  }
  expect_failures = [var.forwards]
}

run "remapped" {
  command = apply
  variables {
    forwards = { https = { guest = "proxy", protocol = "udp", port = 443, address = "fd42:77:1:3::2", vnet_id = "hsp1003" } }
    hairpin  = { "cloud/https" = { source_guest = "cloud", source_address = "fd42:77:1:1::2", source_vnet_id = "hsp1001", forward_key = "https", target_guest = "proxy", target_address = "fd42:77:1:3::2", target_vnet_id = "hsp1003", target_gateway = "fd42:77:1:3::1", protocol = "udp", port = 443 } }
  }
}

run "egress_revoked" {
  command = apply
  variables { egress = { cloud = { address = "fd42:77:1:1::2", vnet_id = "hsp1001", ports = [{ protocol = "udp", port = 123 }, { protocol = "icmp" }] } } }
}

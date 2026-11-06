# Never execute SSH actions during offline mock applies or cleanup.
override_module {
  target = module.proxmox.module.he_teardown
}
mock_provider "system" {}
variables {
  proxmox_ssh   = { host = "192.0.2.10", user = "root" }
  platform_cidr = "10.77.0.0/24"
}


run "without_hairpin" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
  }
  assert {
    condition     = length(var.he_ipv6.hairpin) == 0
    error_message = "without_hairpin contract failed."
  }
}

run "host_config_has_no_hairpin_resources" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "cloud" : ["https", "https"], "proxy-public" : ["https"] } }
  }
  assert {
    condition     = var.he_ipv6.hairpin["cloud"] == toset(["https"]) && output.he_ipv6_status == run.without_hairpin.he_ipv6_status
    error_message = "host_config_has_no_hairpin_resources contract failed."
  }
}

run "reject_unknown_forward" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "cloud" : ["missing"] } }
  }
  expect_failures = [var.he_ipv6]
}

run "reject_empty_set" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "cloud" : [] } }
  }
  expect_failures = [var.he_ipv6]
}

run "reject_bad_names" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "bad/name" : ["https"] } }
  }
  expect_failures = [var.he_ipv6]
}

run "reject_bad_forward_name" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "bad/key" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "cloud" : ["bad/key"] } }
  }
  expect_failures = [var.he_ipv6]
}

run "allow_unreferenced_legacy_forward_key" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "legacy/key" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
  }
  assert {
    condition     = length(var.he_ipv6.hairpin) == 0
    error_message = "allow_unreferenced_legacy_forward_key contract failed."
  }
}

run "off_tolerates_saved_references" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : false, "hairpin" : { "absent" : ["missing"] } }
  }
  assert {
    condition     = output.he_ipv6_status == null
    error_message = "off_tolerates_saved_references contract failed."
  }
}

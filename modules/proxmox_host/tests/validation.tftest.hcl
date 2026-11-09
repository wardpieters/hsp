override_module {
  target = module.he_teardown
}
mock_provider "system" {}
variables {
  proxmox_ssh   = { host = "192.0.2.10", user = "root" }
  platform_cidr = "10.77.0.0/24"
}
run "reject_ipv6_server_in_ipv4_field" {
  command = plan
  variables { he_ipv6 = { "enabled" : true, "server_ipv4" : "2001::", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" } }
  expect_failures = [var.he_ipv6]
}

run "reject_server_ipv4_1580" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : null, "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_local_ipv4_1997" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "::1", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_client_ipv6_2412" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "192.0.2.1/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_client_ipv6_2828" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/63", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_server_ipv6_3255" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:3::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_server_ipv6_3682" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::2", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_server_ipv4_4109" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1\nwhoami", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_routed_prefix_4544" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::1/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_routed_prefix_4974" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:1::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_routed_prefix_5403" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "fd42::/64", "ula_prefix" : "fdab:cdef:1000::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_ula_prefix_5819" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "2001:db8::/48" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_ula_prefix_6244" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/64" }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_mtu_6670" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48", "mtu" : 1279 }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_mtu_7102" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48", "mtu" : 1481 }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_mtu_7534" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48", "mtu" : 1480.5 }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_protected_cidrs_7968" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48", "protected_cidrs" : ["192.168.1.0/24"] }

  }
  expect_failures = [var.he_ipv6]
}

run "reject_protected_cidrs_8438" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "192.0.2.1", "local_ipv4" : "198.51.100.10", "client_ipv6" : "2001:db8:1::2/64", "server_ipv6" : "2001:db8:1::1", "routed_prefix" : "2001:db8:2::/64", "ula_prefix" : "fdab:cdef:1000::/48", "protected_cidrs" : ["fdab:cdef:2000::1/64"] }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_private_tunnel_endpoints" {
  command = plan
  variables {
    he_ipv6 = {
      server_ipv4   = "192.0.2.1", local_ipv4 = "198.51.100.10",
      client_ipv6   = "fdab:cdef::2/64", server_ipv6 = "fdab:cdef::1",
      routed_prefix = "2001:db8:2::/64", ula_prefix = "fdab:cdef:1000::/48"
    }
  }
  expect_failures = [var.he_ipv6]
}

mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  domain                = "home.example.com"
  proxmox_api_token     = "terraform@pve!offline=offline-test-only"
  proxmox_endpoint      = "https://192.168.100.10:8006/"
  pihole_url            = "https://192.168.100.53"
  pihole_password       = "offline-test-only"
  node_name             = "pve"
  platform_cidr         = "10.77.0.0/24"
  host_address          = "192.168.100.10"
  protected_cidrs       = ["192.168.100.0/24"]
  bootstrap_admin_cidrs = ["192.168.100.42/32"]
  dns_servers           = ["192.168.100.53"]
  ntp_servers           = []
  vm_template_id        = 9000
  datastore_id          = "local-lvm"
  ssh_public_keys       = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  proxmox_ssh           = { host = "192.168.100.10", user = "root" }
  guests = {
    proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", role = "public_proxy", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] }
    cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101" }
  }
  connections = []
}
run "reject_ipv6_server_in_ipv4_field" {
  command = plan
  variables { he_ipv6 = { "enabled" : true, "server_ipv4" : "2001::", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } } }
  expect_failures = [var.he_ipv6]
}
run "default_off" {
  command = plan
  variables {
    he_ipv6 = {}

  }
  assert {
    condition     = !var.he_ipv6.enabled && local.he_ipv6_public_address == null
    error_message = "HE configuration must validate and derive the public host address."
  }
}
run "explicit_off" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : false }

  }
  assert {
    condition     = local.he_ipv6_public_address == null
    error_message = "HE configuration must validate and derive the public host address."
  }
}
run "enabled" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  assert {
    condition     = local.he_ipv6_public_address == "2001:470:1f15:4d6::2"
    error_message = "HE configuration must validate and derive the public host address."
  }
}
run "empty_forward_map" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : {} }

  }
  assert {
    condition     = local.he_ipv6_public_address == "2001:470:1f15:4d6::2"
    error_message = "HE configuration must validate and derive the public host address."
  }
}
run "reject_server_ipv4_1580" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : null, "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_local_ipv4_1997" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "::1", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_client_ipv6_2412" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "192.0.2.1/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_client_ipv6_2828" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/63", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_server_ipv6_3255" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d5::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_server_ipv6_3682" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::2", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_server_ipv4_4109" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46\nwhoami", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_routed_prefix_4544" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::1/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_routed_prefix_4974" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f14:4d4::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_routed_prefix_5403" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "fd42::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_ula_prefix_5819" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "2001:db8::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_ula_prefix_6244" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/64", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_mtu_6670" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "mtu" : 1279 }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_mtu_7102" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "mtu" : 1481 }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_mtu_7534" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "mtu" : 1480.5 }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_protected_cidrs_7968" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "protected_cidrs" : ["192.168.1.0/24"] }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_protected_cidrs_8438" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "protected_cidrs" : ["fd42:12::1/64"] }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_port_forwards_8907" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "a" : { "guest" : "proxy-public", "port" : 22 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_port_forwards_9331" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "a" : { "guest" : "proxy-public", "port" : 443 }, "b" : { "guest" : "cloud", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "reject_port_forwards_9794" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "a" : null } }

  }
  expect_failures = [var.he_ipv6]
}
run "unknown_target" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "smtp" : { "guest" : "mail", "port" : 25 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "undeclared_target_port" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "smtp" : { "guest" : "cloud", "port" : 25 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "mismatched_host" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.11", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }

  }
  expect_failures = [var.he_ipv6]
}
run "missing_ssh" {
  command = plan
  variables {
    he_ipv6     = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }
    proxmox_ssh = null
  }
  expect_failures = [var.he_ipv6]
}
run "disabled_saved_settings" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : false, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "smtp" : { "guest" : "absent", "port" : 25 } } }

  }
  assert {
    condition     = local.he_ipv6_public_address == null
    error_message = "HE configuration must validate and derive the public host address."
  }
}
run "reject_egress_only_slot_overflow" {
  command = plan
  variables {
    he_ipv6       = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : {} }
    platform_cidr = "10.0.0.0/8"
    guests        = { cloud = { vm_id = 101, slot = 65536, vnet_id = "hsp101", internet_egress_ports = [{ protocol = "tcp", port = 443 }] } }
  }
  expect_failures = [var.he_ipv6]
}
run "reject_udp_only_forward_target" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } } }
    guests  = { proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "udp", port = 443 }] } }
  }
  expect_failures = [var.he_ipv6]
}

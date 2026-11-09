# Never execute SSH actions during offline mock applies or cleanup.
override_module {
  target = module.ipv6_ingress[0].module.teardown
}
mock_provider "system" { alias = "ingress" }
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
  proxmox_ssh           = { host = "192.0.2.10", user = "root" }
  guests = {
    proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", role = "public_proxy", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] }
    cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101" }
  }
  internet_egress_ports = []
  he_ipv6               = { enabled = true, server_ipv4 = "216.66.84.46", local_ipv4 = "192.168.100.10", client_ipv6 = "2001:470:1f14:4d4::2/64", server_ipv6 = "2001:470:1f14:4d4::1", routed_prefix = "2001:470:1f15:4d6::/64", ula_prefix = "fd42:77:1::/48" }
  connections           = []
}
run "public_ports_do_not_grant_hairpin" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 443 }, { protocol = "tcp", port = 443 }] }
      cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101", public_ports = [{ protocol = "udp", port = 443 }] }
      client       = { vm_id = 103, slot = 3, vnet_id = "hsp103", role = "management" }
    }
  }
  assert {
    condition     = toset(keys(output.ipv6_port_forwards)) == toset(["tcp-443", "udp-443"]) && output.ipv6_port_forwards["tcp-443"].guest == "proxy-public" && output.ipv6_port_forwards["udp-443"].guest == "cloud" && output.ipv6_port_forwards["udp-443"].protocol == "udp"
    error_message = "Public declarations must resolve to unique protocol-aware targets, deduplicating one owner's repeated declarations."
  }
  assert {
    condition     = length(output.ipv6_hairpin) == 0 && length(output.ipv6_egress) == 0 && !contains(keys(output.ipv6_networks), "client") && length([for r in output.policies["client"] : r if startswith(r.comment, "hsp:ipv6:hairpin-")]) == 0
    error_message = "Declaring public listeners must not implicitly authorize client hairpin."
  }
}

run "conflicting_tcp_owners" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 443 }] }
      cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101", public_ports = [{ protocol = "tcp", port = 443 }] }
    }
  }
  expect_failures = [var.he_ipv6]
}
run "conflicting_udp_owners" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "udp", port = 443 }] }
      cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101", public_ports = [{ protocol = "udp", port = 443 }] }
    }
  }
  expect_failures = [var.he_ipv6]
}
run "empty_public_ports" {
  command = plan
  variables { guests = { cloud = { vm_id = 101, slot = 1, vnet_id = "hsp101" } } }
  assert {
    condition     = length(output.ipv6_networks) == 0 && length(output.ipv6_hairpin) == 0 && length(output.ipv6_port_forwards) == 0 && length(module.ipv6_ingress) == 0
    error_message = "Empty declarations without egress need no IPv6 participants."
  }
}
run "retain_egress_after_last_forward" {
  command = plan
  variables { guests = { cloud = { vm_id = 101, slot = 1, vnet_id = "hsp101", internet_egress_ports = [{ protocol = "udp", port = 123 }] } } }
  assert {
    condition     = length(output.ipv6_hairpin) == 0 && length(output.ipv6_port_forwards) == 0 && output.ipv6_networks["cloud"].address == "fd42:77:1:1::2" && length(output.ipv6_egress) == 1
    error_message = "Independent egress survives removing the final public port."
  }
}
run "off" {
  command = plan
  variables { he_ipv6 = {} }
  assert {
    condition     = length(output.ipv6_hairpin) == 0 && length(output.ipv6_networks) == 0 && length(output.ipv6_port_forwards) == 0
    error_message = "HE disabled must leave all IPv6 entries empty."
  }
}
run "hairpin_only_lxc" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "udp", port = 53 }] }
      cloud        = { vm_id = 101, slot = 1, vnet_id = "hsp101", type = "lxc" }
    }
    lxc_template = { file_id = "local:vztmpl/debian.tar.zst" }
    connections  = [{ from = "cloud", to = "proxy-public", protocol = "udp", port = 53 }]
  }
  assert {
    condition     = output.ipv6_hairpin["cloud/udp-53"].target_guest == "proxy-public" && output.ipv6_hairpin["cloud/udp-53"].translated_source_address == "fd42:77:1:2::1" && length(local.he_ipv6_firewall_bridges) == 2
    error_message = "VMs and LXCs receive automatic hairpin and bridge tracking."
  }
}
run "reject_hairpin_slot_overflow" {
  command = plan
  variables {
    connections   = [{ from = "cloud", to = "proxy-public", protocol = "tcp", port = 443 }]
    platform_cidr = "10.0.0.0/8"
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 443 }] }
      cloud        = { vm_id = 101, slot = 65536, vnet_id = "hsp101" }
    }
  }
  expect_failures = [var.he_ipv6]
}

run "web_587_cannot_hairpin_http" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 80 }] }
      web          = { vm_id = 101, slot = 1, vnet_id = "hsp101", internet_egress_ports = [{ protocol = "tcp", port = 587 }] }
    }
  }
  assert {
    condition     = !contains(keys(output.ipv6_hairpin), "web/tcp-80") && length([for r in output.policies["web"] : r if startswith(r.comment, "hsp:ipv6:hairpin-out:")]) == 0
    error_message = "TCP 587 egress must not authorize HTTP hairpin to the public VIP."
  }
}
run "matching_egress_protocol_and_port" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "udp", port = 80 }], internet_egress_ports = [{ protocol = "udp", port = 80 }] }
      web          = { vm_id = 101, slot = 1, vnet_id = "hsp101", internet_egress_ports = [{ protocol = "tcp", port = 80 }, { protocol = "icmp" }] }
    }
  }
  assert {
    condition     = toset(keys(output.ipv6_hairpin)) == toset(["web/tcp-80", "proxy-public/udp-80"]) && output.ipv6_hairpin["proxy-public/udp-80"].source_address == output.ipv6_hairpin["proxy-public/udp-80"].target_address
    error_message = "Hairpin requires an exact TCP/UDP protocol and port match; self-hairpin follows the same rule."
  }
}
run "explicit_connection_is_direction_target_and_protocol_specific" {
  command = plan
  variables {
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }, { protocol = "udp", port = 80 }] }
      web          = { vm_id = 101, slot = 1, vnet_id = "hsp101", public_ports = [{ protocol = "tcp", port = 8080 }] }
      other        = { vm_id = 103, slot = 3, vnet_id = "hsp103" }
    }
    connections = [
      { from = "web", to = "proxy-public", protocol = "tcp", port = 80 },
      { from = "web", to = "proxy-public", protocol = "tcp", port = 80 },
      { from = "proxy-public", to = "web", protocol = "tcp", port = 81 },
      { from = "other", to = "web", protocol = "tcp", port = 80 },
      { from = "web", to = "192.168.100.99", protocol = "tcp", port = 443 },
      { from = "192.168.100.98", to = "proxy-public", protocol = "tcp", port = 443 }
    ]
  }
  assert {
    condition     = toset(keys(output.ipv6_hairpin)) == toset(["web/tcp-80"]) && length(output.ipv6_egress) == 0 && length([for r in output.policies["web"] : r if r.comment == "hsp:ipv6:hairpin-out:80"]) == 1 && length([for r in output.policies["proxy-public"] : r if r.comment == "hsp:ipv6:hairpin-in:80"]) == 1
    error_message = "Only the explicitly authorized directed guest/protocol/port connection may generate hairpin; external addresses, other targets, ports and protocols must not match."
  }
}
run "effective_global_and_role_egress" {
  command = plan
  variables {
    internet_egress_ports = [{ protocol = "udp", port = 53 }]
    guests = {
      proxy-public = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }, { protocol = "udp", port = 53 }] }
      web          = { vm_id = 101, slot = 1, vnet_id = "hsp101", role = "monitoring" }
    }
  }
  assert {
    condition     = toset(keys(output.ipv6_hairpin)) == toset(["proxy-public/udp-53", "web/tcp-80", "web/tcp-443", "web/udp-53"])
    error_message = "Global and role defaults must participate exactly as in effective internet egress."
  }
}

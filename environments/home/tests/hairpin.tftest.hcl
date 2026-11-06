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
  he_ipv6               = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "cloud" : ["https", "https"], "proxy-public" : ["https"] } }
  connections           = []
}

run "hairpin_only_vm" {
  command = plan
  assert {
    condition     = output.ipv6_networks["cloud"].address == "fd42:77:1:1::2" && length(output.ipv6_egress) == 0 && output.ipv6_hairpin["cloud/https"].translated_source_address == "fd42:77:1:2::1" && output.ipv6_hairpin["cloud/https"].public_address == "2001:470:1f15:4d6::2" && output.ipv6_hairpin["cloud/https"].protocol == "tcp"
    error_message = "hairpin_only_vm contract failed."
  }

  assert {
    condition     = toset(keys(output.ipv6_hairpin)) == toset(["cloud/https", "proxy-public/https"]) && toset(keys(output.ipv6_hairpin["cloud/https"])) == toset(["source_guest", "source_address", "source_vnet_id", "forward_key", "public_address", "protocol", "port", "target_guest", "target_address", "target_vnet_id", "translated_source_address"])
    error_message = "Hairpin output must use exact composite keys and field set."
  }
  assert {
    condition     = toset(keys(local.he_ipv6_firewall_bridges)) == toset(["fwbr101i0", "fwbr1002i0"]) && length([for x in output.policies["cloud"] : x if startswith(x.comment, "hsp:ipv6:hairpin-out:")]) == 1 && length([for x in output.policies["cloud"] : x if startswith(x.comment, "hsp:ipv6:public:") || startswith(x.comment, "hsp:ipv6:internet:")]) == 0 && length([for x in output.ipv6_host_requirements : x if strcontains(x.purpose, "hairpin")]) == 0 && length(proxmox_virtual_environment_firewall_rules.host) == 0
    error_message = "Source gets deduplicated exact hairpin grants, owned bridges, and no listener/internet/host acceptance."
  }
}

run "reject_unknown_source" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "missing" : ["https"] } }
  }
  expect_failures = [var.he_ipv6]
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

run "off_tolerates_saved_references" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : false, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : { "absent" : ["missing"] } }
  }
  assert {
    condition     = length(output.ipv6_hairpin) == 0 && length(output.ipv6_networks) == 0 && length(module.ipv6_ingress) == 0
    error_message = "off_tolerates_saved_references contract failed."
  }
}

run "remove_last_grant" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
  }
  assert {
    condition     = !contains(keys(output.ipv6_networks), "cloud") && module.network.networks["cloud"].address == "10.77.0.6"
    error_message = "remove_last_grant contract failed."
  }
}

run "hairpin_only_lxc" {
  command = plan
  variables {
    guests       = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 1, "vnet_id" : "hsp101", "type" : "lxc" } }
    lxc_template = { "file_id" : "local:vztmpl/debian.tar.zst" }
  }
  assert {
    condition     = output.ipv6_hairpin == run.hairpin_only_vm.ipv6_hairpin && output.policies == run.hairpin_only_vm.policies
    error_message = "hairpin_only_lxc contract failed."
  }
}

run "self_hairpin" {
  command = plan
  assert {
    condition     = output.ipv6_hairpin["proxy-public/https"].source_address == output.ipv6_hairpin["proxy-public/https"].target_address && output.ipv6_hairpin["proxy-public/https"].translated_source_address == "fd42:77:1:2::1" && length([for x in output.policies["proxy-public"] : x if x.comment == "hsp:ipv6:hairpin-in:443"]) == 1
    error_message = "self_hairpin contract failed."
  }
}

run "host_firewall_owned" {
  command = plan
  variables {
    manage_host_firewall = true
  }
  assert {
    condition     = output.ipv6_hairpin == run.hairpin_only_vm.ipv6_hairpin && length(proxmox_virtual_environment_firewall_rules.host) == 1 && length([for x in output.host_policy : x if strcontains(x.comment, "hairpin")]) == 0
    error_message = "host_firewall_owned contract failed."
  }
}

run "allow_unreferenced_legacy_forward_key" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "legacy/key" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
  }
  assert {
    condition     = length(output.ipv6_hairpin) == 0 && contains(keys(output.ipv6_port_forwards), "legacy/key")
    error_message = "allow_unreferenced_legacy_forward_key contract failed."
  }
}

run "retain_other_participation" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
    guests  = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 1, "vnet_id" : "hsp101", "internet_egress_ports" : [{ "protocol" : "tcp", "port" : 443 }] } }
  }
  assert {
    condition     = contains(keys(output.ipv6_networks), "cloud") && length(output.ipv6_hairpin) == 0 && contains(keys(output.ipv6_egress), "cloud")
    error_message = "retain_other_participation contract failed."
  }
}

run "retain_forward_participation" {
  command = plan
  variables {
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 }, "cloud" : { "guest" : "cloud", "port" : 8443 } }, "hairpin" : {} }
    guests  = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 1, "vnet_id" : "hsp101", "public_ports" : [{ "protocol" : "tcp", "port" : 8443 }] } }
  }
  assert {
    condition     = contains(keys(output.ipv6_networks), "cloud") && length(output.ipv6_hairpin) == 0 && output.ipv6_port_forwards["cloud"].guest == "cloud"
    error_message = "retain_forward_participation contract failed."
  }
}

run "restrictive_role_requires_explicit_grant" {
  command = plan
  variables {
    guests = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 1, "vnet_id" : "hsp101", "role" : "management" } }
  }
  assert {
    condition     = length([for x in output.policies["cloud"] : x if x.comment == "hsp:ipv6:hairpin-out:443"]) == 1 && length(output.ipv6_egress) == 0
    error_message = "restrictive_role_requires_explicit_grant contract failed."
  }
}

run "restrictive_role_without_grant" {
  command = plan
  variables {
    guests  = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 1, "vnet_id" : "hsp101", "role" : "management" } }
    he_ipv6 = { "enabled" : true, "server_ipv4" : "216.66.84.46", "local_ipv4" : "192.168.100.10", "client_ipv6" : "2001:470:1f14:4d4::2/64", "server_ipv6" : "2001:470:1f14:4d4::1", "routed_prefix" : "2001:470:1f15:4d6::/64", "ula_prefix" : "fd42:77:1::/48", "port_forwards" : { "https" : { "guest" : "proxy-public", "port" : 443 } }, "hairpin" : {} }
  }
  assert {
    condition     = !contains(keys(output.ipv6_networks), "cloud") && length([for x in output.policies["cloud"] : x if strcontains(x.comment, "hairpin")]) == 0
    error_message = "restrictive_role_without_grant contract failed."
  }
}

run "reject_hairpin_slot_overflow" {
  command = plan
  variables {
    platform_cidr = "10.0.0.0/8"
    guests        = { "proxy-public" : { "vm_id" : 1002, "slot" : 2, "vnet_id" : "hsp1002", "role" : "public_proxy", "public_ports" : [{ "protocol" : "tcp", "port" : 80 }, { "protocol" : "tcp", "port" : 443 }] }, "cloud" : { "vm_id" : 101, "slot" : 65536, "vnet_id" : "hsp101" } }
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

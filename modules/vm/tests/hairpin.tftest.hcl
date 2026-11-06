mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
variables {
  domain          = "home.example.com"
  name            = "owncloud"
  node_name       = "pve"
  vm_id           = 100
  vm_template_id  = 9000
  datastore_id    = "local-lvm"
  network         = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100" }
  protected_cidrs = ["192.168.1.0/24", "10.77.0.0/24"]
  dns_servers     = ["192.168.1.53"]
  ntp_servers     = ["192.168.1.1"]
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  public_ports    = [{ protocol = "tcp", port = 443 }]
  allow_rules     = [{ direction = "in", address = "10.77.0.6/32", protocol = "tcp", ports = "8080", description = "private proxy" }]
}
override_resource {
  target = terraform_data.lxc_config
  values = {}
}
run "hairpin_vm" {
  command = plan
  variables {
    network              = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_forwarded_ports = [443]
    protected_ipv6_cidrs = ["2001:470:1f15:4d6::/64"]
    ipv6_hairpin_out     = [{ public_address = "2001:470:1f15:4d6::2", port = 443 }, { public_address = "2001:470:1f15:4d6::2", port = 443 }]
    ipv6_hairpin_in      = [{ gateway = "fd42:77:1:2::1", port = 443 }, { gateway = "fd42:77:1:2::1", port = 443 }]
  }
  assert {
    condition     = length([for r in output.rules : r if r.comment == "hsp:ipv6:hairpin-out:443" && r.type == "out" && r.action == "ACCEPT" && r.source == "fd42:77:1:2::2/128" && r.dest == "2001:470:1f15:4d6::2/128" && r.proto == "tcp" && r.dport == "443"]) == 1
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = length([for r in output.rules : r if r.comment == "hsp:ipv6:hairpin-in:443" && r.type == "in" && r.action == "ACCEPT" && r.source == "fd42:77:1:2::1/128" && r.dest == "fd42:77:1:2::2/128" && r.proto == "tcp" && r.dport == "443"]) == 1
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-out:443") < index([for r in output.rules : r.comment], "hsp:ipv6:protect-out:2001:470:1f15:4d6::/64")
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:ipv6:deny-control:out:137") < index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-out:443") && index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-in:443") < index([for r in output.rules : r.comment], "hsp:ipv6:protect-in:fc00::/7")
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = length([for r in output.rules : r if r.action == "ACCEPT" && r.proto == "tcp" && r.type == "out" && r.dest == "::/0"]) == 0
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = toset([for c in proxmox_virtual_environment_firewall_ipset.this.cidr : c.name]) == toset(["10.77.0.2", "fd42:77:1:2::2", "::"])
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
}
run "hairpin_lxc" {
  command = plan
  variables {
    network              = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_forwarded_ports = [443]
    protected_ipv6_cidrs = ["2001:470:1f15:4d6::/64"]
    ipv6_hairpin_out     = [{ public_address = "2001:470:1f15:4d6::2", port = 443 }, { public_address = "2001:470:1f15:4d6::2", port = 443 }]
    ipv6_hairpin_in      = [{ gateway = "fd42:77:1:2::1", port = 443 }, { gateway = "fd42:77:1:2::1", port = 443 }]
    guest_type           = "lxc"
    lxc_template         = { file_id = "local:vztmpl/debian.tar.zst" }
  }
  assert {
    condition     = length([for r in output.rules : r if r.comment == "hsp:ipv6:hairpin-out:443" && r.type == "out" && r.action == "ACCEPT" && r.source == "fd42:77:1:2::2/128" && r.dest == "2001:470:1f15:4d6::2/128" && r.proto == "tcp" && r.dport == "443"]) == 1
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = length([for r in output.rules : r if r.comment == "hsp:ipv6:hairpin-in:443" && r.type == "in" && r.action == "ACCEPT" && r.source == "fd42:77:1:2::1/128" && r.dest == "fd42:77:1:2::2/128" && r.proto == "tcp" && r.dport == "443"]) == 1
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-out:443") < index([for r in output.rules : r.comment], "hsp:ipv6:protect-out:2001:470:1f15:4d6::/64")
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:ipv6:deny-control:out:137") < index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-out:443") && index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-in:443") < index([for r in output.rules : r.comment], "hsp:ipv6:protect-in:fc00::/7")
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = length([for r in output.rules : r if r.action == "ACCEPT" && r.proto == "tcp" && r.type == "out" && r.dest == "::/0"]) == 0
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
  assert {
    condition     = toset([for c in proxmox_virtual_environment_firewall_ipset.this.cidr : c.name]) == toset(["10.77.0.2", "fd42:77:1:2::2", "::"])
    error_message = "Hairpin grants must be exact, deduplicated, ordered and preserve source enforcement."
  }
}
run "reject_hairpin_without_network" {
  command = plan
  variables {
    ipv6_hairpin_out = [{ public_address = "2001:470:1f15:4d6::2", port = 443 }, { public_address = "2001:470:1f15:4d6::2", port = 443 }]
  }
  expect_failures = [var.ipv6_hairpin_out]
}
run "reject_wrong_gateway" {
  command = plan
  variables {
    network              = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_forwarded_ports = [443]
    ipv6_hairpin_in      = [{ gateway = "fd42:77:1:2::3", port = 443 }]
  }
  expect_failures = [var.ipv6_hairpin_in]
}
run "reject_unforwarded_incoming_port" {
  command = plan
  variables {
    network         = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_hairpin_in = [{ gateway = "fd42:77:1:2::1", port = 443 }, { gateway = "fd42:77:1:2::1", port = 443 }]
  }
  expect_failures = [var.ipv6_hairpin_in]
}
run "reject_non_global_vip" {
  command = plan
  variables {
    network          = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_hairpin_out = [{ public_address = "fd42:77:1:2::2", port = 443 }]
  }
  expect_failures = [var.ipv6_hairpin_out]
}
run "reject_invalid_port" {
  command = plan
  variables {
    network          = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_hairpin_out = [{ public_address = "2001:470:1f15:4d6::2", port = 443.5 }]
  }
  expect_failures = [var.ipv6_hairpin_out]
}
run "baseline_policy" {
  command = plan
  variables { network = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } } }
}
run "empty_hairpin_preserves_policy" {
  command = plan
  variables {
    network          = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1:2::/64", gateway = "fd42:77:1:2::1", address = "fd42:77:1:2::2" } }
    ipv6_hairpin_out = []
    ipv6_hairpin_in  = []
  }
  assert {
    condition     = output.rules == run.baseline_policy.rules
    error_message = "Empty grants must preserve baseline policy exactly."
  }
}

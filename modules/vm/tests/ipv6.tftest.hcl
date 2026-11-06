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
run "vm_ipv6_and_egress" {
  command = plan
  variables {
    network               = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1::/64", gateway = "fd42:77:1::1", address = "fd42:77:1::2" } }
    ipv6_forwarded_ports  = [443]
    protected_ipv6_cidrs  = ["2001:db8:1::/64"]
    internet_egress_ports = [{ protocol = "tcp", port = 443 }, { protocol = "udp", port = 123 }, { protocol = "icmp" }]
  }
  assert {
    condition     = proxmox_virtual_environment_vm.this[0].initialization[0].ip_config[0].ipv6[0].address == "fd42:77:1::2/64" && toset([for c in proxmox_virtual_environment_firewall_ipset.this.cidr : c.name]) == toset(["10.77.0.2", "fd42:77:1::2", "::"])
    error_message = "Enabled VM must receive static ULA and exact anti-spoof source entries."
  }
  assert {
    condition     = toset([for r in output.rules : "${r.proto}:${coalesce(r.dport, "none")}" if r.type == "out" && r.dest == "::/0" && r.action == "ACCEPT"]) == toset(["tcp:443", "udp:123", "ipv6-icmp:none"])
    error_message = "Effective configured TCP/UDP/ICMP must apply to IPv6 with no ICMP port."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:ipv6:protect-out:2001:db8:1::/64") < index([for r in output.rules : r.comment], "hsp:ipv6:internet:tcp:443") && !proxmox_virtual_environment_firewall_options.this.ndp && !proxmox_virtual_environment_firewall_options.this.radv
    error_message = "Protected networks and static control policy must precede broad internet allowances."
  }
}
run "lxc_egress_only" {
  command = plan
  variables {
    guest_type            = "lxc"
    lxc_template          = { file_id = "local:vztmpl/debian.tar.zst" }
    network               = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1::/64", gateway = "fd42:77:1::1", address = "fd42:77:1::2" } }
    internet_egress_ports = [{ protocol = "icmp" }]
  }
  assert {
    condition     = proxmox_virtual_environment_container.this[0].initialization[0].ip_config[0].ipv6[0].gateway == "fd42:77:1::1" && length([for r in output.rules : r if r.comment == "hsp:ipv6:public:tcp:443"]) == 0 && proxmox_virtual_environment_firewall_options.this.container_id == 100
    error_message = "An egress-only LXC gets IPv6 but no public inbound permission."
  }
  assert {
    condition     = length([for r in output.rules : r if r.proto == "icmpv6" && r.dport == "2" && r.action == "ACCEPT"]) == 2 && length([for r in output.rules : r if r.comment == "hsp:ipv6:deny-control:out:137" && r.action == "DROP"]) == 1
    error_message = "Required PMTU errors remain allowed while router redirects remain denied."
  }
}
run "inbound_only_no_internet" {
  command = plan
  variables {
    network              = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1::/64", gateway = "fd42:77:1::1", address = "fd42:77:1::2" } }
    ipv6_forwarded_ports = [443]
  }
  assert {
    condition     = length([for r in output.rules : r if r.type == "out" && r.action == "ACCEPT" && r.dest == "::/0"]) == 0 && length([for r in output.rules : r if r.comment == "hsp:ipv6:public:tcp:443"]) == 1
    error_message = "Public ingress must not grant new IPv6 internet initiation."
  }
}
run "reject_unlisted_forward" {
  command = plan
  variables { ipv6_forwarded_ports = [25] }
  expect_failures = [var.ipv6_forwarded_ports]
}
run "reject_ipv6_wrong_offsets" {
  command = plan
  variables { network = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100", ipv6 = { cidr = "fd42:77:1::/64", gateway = "fd42:77:1::3", address = "fd42:77:1::2" } } }
  expect_failures = [var.network]
}

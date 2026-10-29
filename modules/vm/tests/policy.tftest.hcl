mock_provider "proxmox" {}
variables {
  name            = "owncloud"
  node_name       = "pve"
  vm_id           = 100
  template_id     = 9000
  datastore_id    = "local-lvm"
  network         = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100" }
  protected_cidrs = ["192.168.1.0/24", "10.77.0.0/24"]
  dns_servers     = ["192.168.1.53"]
  ntp_servers     = ["192.168.1.1"]
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  public_ports    = [{ protocol = "tcp", port = 443 }]
  allow_rules     = [{ direction = "in", address = "10.77.0.6/32", protocol = "tcp", ports = "8080", description = "private proxy" }]
}
run "stopped_and_isolated" {
  command = plan
  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[0].backup
    error_message = "VM disks must be included in backups by default."
  }
  assert {
    condition     = !proxmox_virtual_environment_vm.this.started && !proxmox_virtual_environment_vm.this.on_boot && proxmox_virtual_environment_vm.this.network_device[0].firewall
    error_message = "New guests must remain stopped with NIC enforcement enabled."
  }
  assert {
    condition     = proxmox_virtual_environment_firewall_options.this.enabled && proxmox_virtual_environment_firewall_options.this.input_policy == "DROP" && proxmox_virtual_environment_firewall_options.this.output_policy == "DROP" && proxmox_virtual_environment_firewall_options.this.macfilter && proxmox_virtual_environment_firewall_options.this.ipfilter && !proxmox_virtual_environment_firewall_options.this.ndp && !proxmox_virtual_environment_firewall_options.this.dhcp
    error_message = "Filtering must be enabled and fail closed."
  }
  assert {
    condition     = length(proxmox_virtual_environment_firewall_ipset.this.cidr) == 1 && proxmox_virtual_environment_firewall_ipset.this.cidr[0].name == "10.77.0.2"
    error_message = "Allow exactly the assigned host IP using Proxmox's canonical bare-address form to avoid /32 replacement drift."
  }
  assert {
    condition     = output.rules[0].action == "DROP" && output.rules[0].source == "::/0" && output.rules[1].dest == "::/0"
    error_message = "IPv6 must not bypass IPv4 policy."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:protect-in:192.168.1.0/24") < index([for r in output.rules : r.comment], "hsp:public:tcp:443")
    error_message = "Broad public rules must never precede protected-network drops."
  }
  assert {
    condition     = length([for r in output.rules : r if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == 0
    error_message = "Guests must have no internet egress by default, including when public ingress is enabled."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:allow:private proxy") < index([for r in output.rules : r.comment], "hsp:protect-in:10.77.0.0/24")
    error_message = "Explicit dependencies must be usable before the default platform block."
  }
}
run "explicit_internet_egress_ports" {
  command = plan
  variables {
    internet_egress_ports = [{ protocol = "tcp", port = 8443 }, { protocol = "udp", port = 3478 }]
  }
  assert {
    condition     = toset([for r in output.rules : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["tcp:8443", "udp:3478"])
    error_message = "Internet egress must allow only the explicit TCP/UDP destination ports, without implicit HTTP/HTTPS."
  }
  assert {
    condition     = alltrue([for i, r in output.rules : i > index([for rule in output.rules : rule.comment], "hsp:protect-out:192.168.1.0/24") if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"])
    error_message = "Internet allowances must follow protected-network drops so they cannot grant LAN access."
  }
}
run "backup_disabled" {
  command = plan
  variables { backup = false }
  assert {
    condition     = !proxmox_virtual_environment_vm.this.disk[0].backup
    error_message = "A VM can explicitly exclude its managed disk from backups."
  }
}
run "reject_public_ssh" {
  command = plan
  variables { public_ports = [{ protocol = "tcp", port = 22 }] }
  expect_failures = [var.public_ports]
}
run "reject_internet_egress_protocol" {
  command = plan
  variables { internet_egress_ports = [{ protocol = "icmp", port = 443 }] }
  expect_failures = [var.internet_egress_ports]
}
run "reject_internet_egress_zero_port" {
  command = plan
  variables { internet_egress_ports = [{ protocol = "tcp", port = 0 }] }
  expect_failures = [var.internet_egress_ports]
}
run "reject_internet_egress_large_port" {
  command = plan
  variables { internet_egress_ports = [{ protocol = "udp", port = 65536 }] }
  expect_failures = [var.internet_egress_ports]
}
run "reject_internet_egress_fractional_port" {
  command = plan
  variables { internet_egress_ports = [{ protocol = "tcp", port = 443.5 }] }
  expect_failures = [var.internet_egress_ports]
}

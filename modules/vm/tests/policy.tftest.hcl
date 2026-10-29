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
  allow_updates   = true
  allow_rules     = [{ direction = "in", address = "10.77.0.6/32", protocol = "tcp", ports = "8080", description = "private proxy" }]
}
run "stopped_and_isolated" {
  command = plan
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
    condition     = index([for r in output.rules : r.comment], "hsp:protect-in:192.168.1.0/24") < index([for r in output.rules : r.comment], "hsp:public:tcp:443") && index([for r in output.rules : r.comment], "hsp:protect-out:192.168.1.0/24") < index([for r in output.rules : r.comment], "hsp:updates")
    error_message = "Broad public/update rules must never precede protected-network drops."
  }
  assert {
    condition     = index([for r in output.rules : r.comment], "hsp:allow:private proxy") < index([for r in output.rules : r.comment], "hsp:protect-in:10.77.0.0/24")
    error_message = "Explicit dependencies must be usable before the default platform block."
  }
}
run "reject_public_ssh" {
  command = plan
  variables { public_ports = [{ protocol = "tcp", port = 22 }] }
  expect_failures = [var.public_ports]
}

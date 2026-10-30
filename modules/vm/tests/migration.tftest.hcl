mock_provider "proxmox" {}

run "legacy_vm_state" {
  command   = apply
  state_key = "migration"
  module { source = "./tests/fixtures/legacy" }
}

run "migrate_without_vm_or_firewall_replacement" {
  command   = plan
  state_key = "migration"
  variables {
    name            = "migration-vm"
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
  assert {
    condition     = proxmox_virtual_environment_vm.this[0].id == run.legacy_vm_state.vm_resource_id && length(proxmox_virtual_environment_container.this) == 0
    error_message = "The existing unindexed VM must move to [0] with its identity preserved and no LXC conversion."
  }
  assert {
    condition     = proxmox_virtual_environment_firewall_options.this.id == run.legacy_vm_state.firewall_ids.options && proxmox_virtual_environment_firewall_ipset.this.id == run.legacy_vm_state.firewall_ids.ipset && proxmox_virtual_environment_firewall_rules.this.id == run.legacy_vm_state.firewall_ids.rules
    error_message = "Existing firewall resources must keep their identities during VM state migration."
  }
  assert {
    condition     = output.rules == run.legacy_vm_state.rules
    error_message = "An unchanged VM must retain its complete pre-LXC policy."
  }
}

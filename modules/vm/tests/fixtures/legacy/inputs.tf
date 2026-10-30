# Frozen VM-only configuration from before LXC support. No real infrastructure
# is created: tests/migration.tftest.hcl always uses a mocked provider.
locals {
  name                   = "migration-vm"
  node_name              = "pve"
  vm_id                  = 100
  template_id            = 9000
  datastore_id           = "local-lvm"
  network                = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100" }
  started                = false
  on_boot                = false
  cores                  = 2
  memory_mb              = 2048
  disk_gb                = 16
  backup                 = true
  username               = "ward"
  ssh_public_keys        = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  protected_cidrs        = ["192.168.1.0/24", "10.77.0.0/24"]
  dns_servers            = ["192.168.1.53"]
  ntp_servers            = ["192.168.1.1"]
  internet_egress_ports  = []
  public_ports_lan_cidrs = []
  service_access_cidrs   = []
  public_ports           = [{ protocol = "tcp", port = 443 }]
  allow_rules            = [{ direction = "in", address = "10.77.0.6/32", protocol = "tcp", ports = "8080", description = "private proxy" }]
}

output "vm_resource_id" { value = proxmox_virtual_environment_vm.this.id }
output "firewall_ids" {
  value = {
    options = proxmox_virtual_environment_firewall_options.this.id
    ipset   = proxmox_virtual_environment_firewall_ipset.this.id
    rules   = proxmox_virtual_environment_firewall_rules.this.id
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = local.name
  node_name   = local.node_name
  vm_id       = local.vm_id
  description = "Managed by hsp Terraform; isolated service VM."
  tags        = ["hsp", "terraform"]
  started     = local.started
  on_boot     = local.on_boot
  # Never inherit extra clone interfaces or host devices from an unsuitable template.
  clone {
    vm_id        = local.template_id
    full         = true
    datastore_id = local.datastore_id
  }
  cpu { cores = local.cores }
  memory { dedicated = local.memory_mb }
  disk {
    interface    = "scsi0"
    datastore_id = local.datastore_id
    size         = local.disk_gb
    discard      = "on"
    backup       = local.backup
  }
  agent {
    enabled = true
    wait_for_ip { disabled = true }
  }
  network_device {
    bridge   = local.network.vnet_id
    model    = "virtio"
    firewall = true
  }
  initialization {
    datastore_id = local.datastore_id
    dns {
      domain  = "home.ward.nl"
      servers = local.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${local.network.address}/30"
        gateway = local.network.gateway
      }
    }
    user_account {
      username = local.username
      keys     = local.ssh_public_keys
    }
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "this" {
  node_name = local.node_name
  vm_id     = proxmox_virtual_environment_vm.this.vm_id
  name      = "ipfilter-net0"
  # Proxmox returns single IPv4 hosts without /32. Match that canonical form
  # so the provider does not replace an otherwise unchanged anti-spoofing set.
  cidr { name = local.network.address }
}
resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name     = local.node_name
  vm_id         = proxmox_virtual_environment_vm.this.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "DROP"
  ipfilter      = true
  macfilter     = true
  dhcp          = false
  ndp           = false
  radv          = false
  log_level_in  = "info"
  log_level_out = "info"
}
resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name = local.node_name
  vm_id     = proxmox_virtual_environment_vm.this.vm_id
  dynamic "rule" {
    for_each = local.rules
    content {
      type    = rule.value.type
      action  = rule.value.action
      source  = rule.value.source
      dest    = rule.value.dest
      proto   = rule.value.proto
      dport   = rule.value.dport
      comment = rule.value.comment
      enabled = true
      iface   = "net0"
      log     = rule.value.action == "DROP" ? "info" : "nolog"
    }
  }
}
output "vm_id" { value = proxmox_virtual_environment_vm.this.vm_id }
output "rules" { value = local.rules }

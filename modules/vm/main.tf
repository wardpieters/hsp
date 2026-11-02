resource "proxmox_virtual_environment_vm" "this" {
  count       = var.guest_type == "vm" ? 1 : 0
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Managed by hsp Terraform; isolated service VM."
  tags        = ["hsp", "terraform"]
  started     = var.started
  on_boot     = var.on_boot
  # Never inherit extra clone interfaces or host devices from an unsuitable template.
  clone {
    vm_id        = var.vm_template_id
    full         = true
    datastore_id = var.datastore_id
  }
  cpu { cores = var.cores }
  memory { dedicated = var.memory_mb }
  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_id
    size         = var.disk_gb
    ssd          = var.ssd
    discard      = "on"
    backup       = var.backup
  }
  dynamic "disk" {
    for_each = var.extra_disks
    content {
      interface    = disk.key
      datastore_id = disk.value.datastore_id == null ? var.datastore_id : disk.value.datastore_id
      size         = disk.value.size_gb
      ssd          = disk.value.ssd
      discard      = "on"
      backup       = disk.value.backup
    }
  }
  agent {
    enabled = true
    wait_for_ip { disabled = true }
  }
  network_device {
    bridge   = var.network.vnet_id
    model    = "virtio"
    firewall = true
  }
  initialization {
    datastore_id = var.datastore_id
    dns {
      domain  = var.domain
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${var.network.address}/30"
        gateway = var.network.gateway
      }
    }
    user_account {
      username = var.username
      keys     = var.ssh_public_keys
    }
  }
}

moved {
  from = proxmox_virtual_environment_vm.this
  to   = proxmox_virtual_environment_vm.this[0]
}

locals {
  guest_id = var.guest_type == "vm" ? proxmox_virtual_environment_vm.this[0].vm_id : proxmox_virtual_environment_container.this[0].vm_id
}

resource "proxmox_virtual_environment_firewall_ipset" "this" {
  node_name    = var.node_name
  vm_id        = var.guest_type == "vm" ? local.guest_id : null
  container_id = var.guest_type == "lxc" ? local.guest_id : null
  name         = "ipfilter-net0"
  # Proxmox returns single IPv4 hosts without /32. Match that canonical form
  # so the provider does not replace an otherwise unchanged anti-spoofing set.
  cidr { name = var.network.address }
}
resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name     = var.node_name
  vm_id         = var.guest_type == "vm" ? local.guest_id : null
  container_id  = var.guest_type == "lxc" ? local.guest_id : null
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
  node_name    = var.node_name
  vm_id        = var.guest_type == "vm" ? local.guest_id : null
  container_id = var.guest_type == "lxc" ? local.guest_id : null
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
output "vm_id" { value = local.guest_id }
output "guest_type" { value = length(proxmox_virtual_environment_container.this) == 1 ? "lxc" : "vm" }
output "rules" { value = local.rules }

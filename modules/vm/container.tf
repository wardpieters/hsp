resource "proxmox_virtual_environment_container" "this" {
  count                                = var.guest_type == "lxc" ? 1 : 0
  node_name                            = var.node_name
  vm_id                                = var.vm_id
  description                          = "Managed by hsp Terraform; isolated service LXC."
  tags                                 = ["hsp", "terraform"]
  unprivileged                         = true
  started                              = var.started
  start_on_boot                        = var.on_boot
  delete_unreferenced_disks_on_destroy = false

  cpu { cores = var.cores }
  memory {
    dedicated = var.memory_mb
    swap      = 0
  }
  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }
  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume = mount_point.value.datastore_id == null ? var.datastore_id : mount_point.value.datastore_id
      size   = "${mount_point.value.size_gb}G"
      path   = mount_point.value.path
      backup = mount_point.value.backup
    }
  }
  features {
    nesting = var.nesting
    fuse    = false
    keyctl  = false
    mknod   = false
  }
  network_interface {
    name     = "eth0"
    bridge   = var.network.vnet_id
    enabled  = true
    firewall = true
  }
  initialization {
    hostname = var.name
    dns {
      domain  = "home.ward.nl"
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${var.network.address}/30"
        gateway = var.network.gateway
      }
    }
    user_account { keys = var.ssh_public_keys }
  }
  operating_system {
    template_file_id = try(var.lxc_template.file_id, null)
    type             = try(var.lxc_template.os_type, null)
  }
}

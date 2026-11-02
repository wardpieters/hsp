mock_provider "proxmox" {}
mock_provider "restful" {}

variables {
  domain          = "home.example.com"
  name            = "cloud"
  node_name       = "pve"
  vm_id           = 100
  vm_template_id  = 9000
  datastore_id    = "local-lvm"
  network         = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100" }
  protected_cidrs = ["192.168.1.0/24", "10.77.0.0/24"]
  dns_servers     = ["192.168.1.53"]
  ntp_servers     = []
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
}

run "default_vm_has_only_root_disk" {
  command = plan
  assert {
    condition     = length(proxmox_virtual_environment_vm.this[0].disk) == 1 && proxmox_virtual_environment_vm.this[0].disk[0].interface == "scsi0" && proxmox_virtual_environment_vm.this[0].disk[0].size == 16 && proxmox_virtual_environment_vm.this[0].disk[0].datastore_id == "local-lvm" && proxmox_virtual_environment_vm.this[0].disk[0].backup && proxmox_virtual_environment_vm.this[0].disk[0].ssd == false
    error_message = "Omitting extra_disks must preserve the existing root disk, backup and SSD defaults."
  }
}

run "managed_vm_data_disks" {
  command = plan
  variables {
    disk_gb = 24
    backup  = false
    ssd     = true
    extra_disks = {
      scsi30 = { size_gb = 1 }
      scsi2  = { size_gb = 8, datastore_id = "fast-lvm", backup = false, ssd = false }
      scsi1  = { size_gb = 100, ssd = true }
    }
  }
  assert {
    condition     = length(proxmox_virtual_environment_vm.this[0].disk) == 4
    error_message = "The root disk and all requested data disks must be attached."
  }
  assert {
    condition = { for disk in proxmox_virtual_environment_vm.this[0].disk : disk.interface => {
      size = disk.size, datastore = disk.datastore_id, backup = disk.backup, discard = disk.discard, ssd = disk.ssd
      } } == {
      scsi0  = { size = 24, datastore = "local-lvm", backup = false, discard = "on", ssd = true }
      scsi1  = { size = 100, datastore = "local-lvm", backup = true, discard = "on", ssd = true }
      scsi2  = { size = 8, datastore = "fast-lvm", backup = false, discard = "on", ssd = false }
      scsi30 = { size = 1, datastore = "local-lvm", backup = true, discard = "on", ssd = false }
    }
    error_message = "Interface identity, sizes, storage overrides and independent backup/SSD flags must match each requested disk."
  }
}

run "extra_ssd_does_not_enable_root_ssd" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 100, ssd = true } } }
  assert {
    condition     = { for disk in proxmox_virtual_environment_vm.this[0].disk : disk.interface => disk.ssd } == { scsi0 = false, scsi1 = true }
    error_message = "Extra disks must enable SSD emulation independently of the default root disk."
  }
}

run "reject_root_ssd_on_lxc" {
  command = plan
  variables {
    guest_type   = "lxc"
    lxc_template = { file_id = "local:vztmpl/debian-test.tar.zst" }
    ssd          = true
  }
  expect_failures = [var.ssd]
}

run "reject_extra_disks_on_lxc" {
  command = plan
  variables {
    guest_type   = "lxc"
    lxc_template = { file_id = "local:vztmpl/debian-test.tar.zst" }
    extra_disks  = { scsi1 = { size_gb = 100 } }
  }
  expect_failures = [var.extra_disks]
}

run "reject_root_interface" {
  command = plan
  variables { extra_disks = { scsi0 = { size_gb = 100 } } }
  expect_failures = [var.extra_disks]
}

run "reject_out_of_range_interface" {
  command = plan
  variables { extra_disks = { scsi31 = { size_gb = 100 } } }
  expect_failures = [var.extra_disks]
}

run "reject_noncanonical_interface" {
  command = plan
  variables { extra_disks = { scsi01 = { size_gb = 100 } } }
  expect_failures = [var.extra_disks]
}

run "reject_other_interface_type" {
  command = plan
  variables { extra_disks = { sata1 = { size_gb = 100 } } }
  expect_failures = [var.extra_disks]
}

run "reject_zero_disk_size" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 0 } } }
  expect_failures = [var.extra_disks]
}

run "reject_negative_disk_size" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = -1 } } }
  expect_failures = [var.extra_disks]
}

run "reject_fractional_disk_size" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 1.5 } } }
  expect_failures = [var.extra_disks]
}

run "reject_null_disk_size" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = null } } }
  expect_failures = [var.extra_disks]
}

run "reject_null_disk_entry" {
  command = plan
  variables { extra_disks = { scsi1 = null } }
  expect_failures = [var.extra_disks]
}

run "reject_host_path_storage" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 100, datastore_id = "/dev/sdb" } } }
  expect_failures = [var.extra_disks]
}

run "reject_existing_volume_storage" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 100, datastore_id = "local-lvm:vm-100-disk-1" } } }
  expect_failures = [var.extra_disks]
}

run "reject_empty_storage_override" {
  command = plan
  variables { extra_disks = { scsi1 = { size_gb = 100, datastore_id = "" } } }
  expect_failures = [var.extra_disks]
}

run "reject_invalid_inherited_storage" {
  command = plan
  variables {
    datastore_id = "/dev/sdb"
    extra_disks  = { scsi1 = { size_gb = 100 } }
  }
  expect_failures = [var.extra_disks]
}

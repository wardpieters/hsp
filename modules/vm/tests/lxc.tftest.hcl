mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
variables {
  name            = "files"
  node_name       = "pve"
  vm_id           = 100
  guest_type      = "lxc"
  lxc_template    = { file_id = "local:vztmpl/debian-test.tar.zst" }
  datastore_id    = "local-lvm"
  network         = { address = "10.77.0.2", gateway = "10.77.0.1", cidr = "10.77.0.0/30", vnet_id = "hsp100" }
  protected_cidrs = ["192.168.1.0/24", "10.77.0.0/24"]
  dns_servers     = ["192.168.1.53"]
  ntp_servers     = []
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
}
run "managed_mount_volumes" {
  command = plan
  variables {
    mount_points = [
      { path = "/srv/data", size_gb = 50 },
      { path = "/srv/cache", size_gb = 8, datastore_id = "fast-lvm", backup = false },
    ]
  }
  assert {
    condition     = length(proxmox_virtual_environment_container.this[0].mount_point) == 2
    error_message = "Each requested mount must allocate a managed volume."
  }
  assert {
    condition     = try(proxmox_virtual_environment_container.this[0].mount_point[0].volume == "local-lvm" && proxmox_virtual_environment_container.this[0].mount_point[0].size == "50G" && proxmox_virtual_environment_container.this[0].mount_point[0].path == "/srv/data" && proxmox_virtual_environment_container.this[0].mount_point[0].backup && proxmox_virtual_environment_container.this[0].mount_point[1].volume == "fast-lvm" && proxmox_virtual_environment_container.this[0].mount_point[1].size == "8G" && proxmox_virtual_environment_container.this[0].mount_point[1].path == "/srv/cache" && !proxmox_virtual_environment_container.this[0].mount_point[1].backup, false)
    error_message = "Mount order, size, container path, default/override storage and per-mount backup flags must be preserved."
  }
}
run "raw_lxc_configuration_payload" {
  command = plan
  variables {
    proxmox_ssh = { host = "192.168.1.10", user = "root" }
    lxc_mounts = [
      "/dev/dri dev/dri none bind,optional,create=dir",
      "/dev/dri/card0 dev/dri/card0 none bind,optional,create=file",
      "/dev/dri/renderD128 dev/renderD128 none bind,optional,create=file",
    ]
    lxc_cgroups = { "devices.allow" = ["c 226:0 rwm", "c 226:128 rwm", "c 29:0 rwm"] }
  }
  assert {
    condition = jsondecode(base64decode(terraform_data.lxc_config[0].input.payload)).entries == [
      ["lxc.mount.entry", "/dev/dri dev/dri none bind,optional,create=dir"],
      ["lxc.mount.entry", "/dev/dri/card0 dev/dri/card0 none bind,optional,create=file"],
      ["lxc.mount.entry", "/dev/dri/renderD128 dev/renderD128 none bind,optional,create=file"],
      ["lxc.cgroup2.devices.allow", "c 226:0 rwm"],
      ["lxc.cgroup2.devices.allow", "c 226:128 rwm"],
      ["lxc.cgroup2.devices.allow", "c 29:0 rwm"],
    ]
    error_message = "Raw LXC inputs must preserve all repeated mount/cgroup entries and the requested render destination."
  }
}
run "raw_lxc_defaults_need_no_ssh" {
  command = plan
  assert {
    condition     = length(terraform_data.lxc_config) == 0
    error_message = "Ordinary LXC guests must not require or attempt SSH."
  }
}
run "reject_raw_mounts_without_ssh" {
  command = plan
  variables { lxc_mounts = ["/dev/dri dev/dri none bind,optional,create=dir"] }
  expect_failures = [var.proxmox_ssh]
}
run "reject_raw_mounts_on_vm" {
  command = plan
  variables {
    guest_type     = "vm"
    vm_template_id = 9000
    proxmox_ssh    = { host = "pve", user = "root" }
    lxc_mounts     = ["/dev/dri dev/dri none bind,optional,create=dir"]
  }
  expect_failures = [var.lxc_mounts]
}
run "reject_raw_cgroups_on_vm" {
  command = plan
  variables {
    guest_type     = "vm"
    vm_template_id = 9000
    proxmox_ssh    = { host = "pve", user = "root" }
    lxc_cgroups    = { "devices.allow" = ["c 226:0 rwm"] }
  }
  expect_failures = [var.lxc_cgroups]
}
run "reject_multiline_mount" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_mounts  = ["/dev/dri dev/dri none bind\nlxc.apparmor.profile: unconfined"]
  }
  expect_failures = [var.lxc_mounts]
}
run "reject_multiline_cgroup" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_cgroups = { "devices.allow" = ["c 226:0 rwm\nlxc.apparmor.profile: unconfined"] }
  }
  expect_failures = [var.lxc_cgroups]
}
run "reject_invalid_cgroup_key" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_cgroups = { "devices.allow: a" = ["c 226:0 rwm"] }
  }
  expect_failures = [var.lxc_cgroups]
}
run "reject_duplicate_mount" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_mounts  = ["/dev/dri dev/dri none bind", "/dev/dri dev/dri none bind"]
  }
  expect_failures = [var.lxc_mounts]
}
run "reject_cgroup_surrounding_whitespace" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_cgroups = { "devices.allow" = [" c 226:128 rwm "] }
  }
  expect_failures = [var.lxc_cgroups]
}
run "reject_uppercase_cgroup_key" {
  command = plan
  variables {
    proxmox_ssh = { host = "pve", user = "root" }
    lxc_cgroups = { "devices.Allow" = ["c 226:128 rwm"] }
  }
  expect_failures = [var.lxc_cgroups]
}
run "mount_sizes_match_proxmox_readback" {
  command = plan
  variables {
    mount_points = [
      { path = "/gib", size_gb = 32 },
      { path = "/below-tib", size_gb = 1023 },
      { path = "/tib", size_gb = 1024 },
      { path = "/nonintegral-tib", size_gb = 1536 },
      { path = "/three-tib", size_gb = 3072 },
      { path = "/above-three-tib", size_gb = 3073 },
      { path = "/large", size_gb = 1048576 },
    ]
  }
  assert {
    condition     = [for m in proxmox_virtual_environment_container.this[0].mount_point : m.size] == ["32G", "1023G", "1T", "1536G", "3T", "3073G", "1024T"]
    error_message = "Mount sizes must match Proxmox's exact-unit read-back without rounding or changing capacity."
  }
  assert {
    condition     = alltrue([for m in proxmox_virtual_environment_container.this[0].mount_point : try(length(m.mount_options) == 0, false)])
    error_message = "Unconfigured mount options must match Proxmox's empty-list read-back."
  }
}
run "reject_mount_on_vm" {
  command = plan
  variables {
    guest_type     = "vm"
    vm_template_id = 9000
    mount_points   = [{ path = "/srv/data", size_gb = 50 }]
  }
  expect_failures = [var.mount_points]
}
run "reject_mount_relative_path" {
  command = plan
  variables { mount_points = [{ path = "srv/data", size_gb = 50 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_root_path" {
  command = plan
  variables { mount_points = [{ path = "/", size_gb = 50 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_parent_path" {
  command = plan
  variables { mount_points = [{ path = "/srv/../data", size_gb = 50 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_dot_path" {
  command = plan
  variables { mount_points = [{ path = "/srv/./data", size_gb = 50 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_empty_path_component" {
  command = plan
  variables { mount_points = [{ path = "/srv//data", size_gb = 50 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_duplicate_path" {
  command = plan
  variables { mount_points = [{ path = "/srv/data", size_gb = 50 }, { path = "/srv/data", size_gb = 8 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_zero_size" {
  command = plan
  variables { mount_points = [{ path = "/srv/data", size_gb = 0 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_fractional_size" {
  command = plan
  variables { mount_points = [{ path = "/srv/data", size_gb = 1.5 }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_host_bind_source" {
  command = plan
  variables { mount_points = [{ path = "/srv/data", size_gb = 50, datastore_id = "/etc" }] }
  expect_failures = [var.mount_points]
}
run "reject_mount_existing_volume_source" {
  command = plan
  variables { mount_points = [{ path = "/srv/data", size_gb = 50, datastore_id = "local-lvm:vm-100-disk-0" }] }
  expect_failures = [var.mount_points]
}
run "reject_lxc_host_path_datastore" {
  command = plan
  variables { datastore_id = "/etc" }
  expect_failures = [var.datastore_id]
}
run "reject_lxc_backup_false" {
  command = plan
  variables { backup = false }
  expect_failures = [var.backup]
}
run "reject_missing_lxc_template" {
  command = plan
  variables { lxc_template = null }
  expect_failures = [var.lxc_template]
}
run "reject_unmanaged_lxc_template" {
  command = plan
  variables { lxc_template = { file_id = "local:vztmpl/test.tar.zst", os_type = "unmanaged" } }
  expect_failures = [var.lxc_template]
}
run "reject_iso_as_lxc_template" {
  command = plan
  variables { lxc_template = { file_id = "local:iso/test.iso" } }
  expect_failures = [var.lxc_template]
}
run "reject_lxc_autostart_before_activation" {
  command = plan
  variables { on_boot = true }
  expect_failures = [var.on_boot]
}
run "lxc_explicit_activation" {
  command = plan
  variables {
    started = true
    on_boot = true
  }
  assert {
    condition     = proxmox_virtual_environment_container.this[0].started && proxmox_virtual_environment_container.this[0].start_on_boot
    error_message = "Explicitly activated LXC guests must honor started and on_boot."
  }
}
run "lxc_nesting_is_opt_in" {
  command   = apply
  state_key = "lxc_nesting_is_opt_in"
  variables { nesting = true }
  assert {
    condition     = restful_resource.nesting[0].body.features == "nesting=1" && restful_resource.nesting[0].create_method == "PUT" && restful_resource.nesting[0].delete_method == "PUT"
    error_message = "Nesting must be managed by feature-only REST PUT requests without unrelated flags or container deletion."
  }
  assert {
    condition     = proxmox_virtual_environment_container.this[0].features[0].nesting && proxmox_virtual_environment_container.this[0].unprivileged && !proxmox_virtual_environment_container.this[0].features[0].keyctl && !proxmox_virtual_environment_container.this[0].features[0].fuse && !proxmox_virtual_environment_container.this[0].features[0].mknod
    error_message = "Opting into nesting must enable only that feature while keeping the container unprivileged."
  }
}
run "lxc_nesting_disable_is_explicit" {
  command   = apply
  state_key = "lxc_nesting_disable_is_explicit"
  assert {
    condition     = restful_resource.nesting[0].body.features == "nesting=0"
    error_message = "Disabling nesting must send an explicit zero."
  }
}
run "lxc_preserves_explicit_disabled_features" {
  command   = apply
  state_key = "lxc_preserves_explicit_disabled_features"
  variables { nesting = true }
  override_data {
    override_during = plan
    target          = data.restful_resource.container_features[0]
    values          = { output = { features = "keyctl=0,nesting=0,fuse=0" } }
  }
  assert {
    condition     = restful_resource.nesting[0].body.features == "fuse=0,keyctl=0,nesting=1" && restful_resource.nesting[0].delete_body.features == "fuse=0,keyctl=0,nesting=0"
    error_message = "Existing disabled flags must be preserved across updates and destruction."
  }
}
run "lxc_rejects_enabled_unrelated_features" {
  command   = apply
  state_key = "lxc_rejects_enabled_unrelated_features"
  override_data {
    override_during = plan
    target          = data.restful_resource.container_features[0]
    values          = { output = { features = "keyctl=1,nesting=0" } }
  }
  expect_failures = [restful_resource.nesting]
}
run "reject_nesting_on_vm" {
  command = plan
  variables {
    guest_type     = "vm"
    vm_template_id = 9000
    nesting        = true
  }
  expect_failures = [var.nesting]
}
run "container_firewall_targets_lxc" {
  command = plan
  assert {
    condition     = length(proxmox_virtual_environment_vm.this) == 0 && length(proxmox_virtual_environment_container.this) == 1 && proxmox_virtual_environment_container.this[0].unprivileged && !proxmox_virtual_environment_container.this[0].started && !proxmox_virtual_environment_container.this[0].start_on_boot
    error_message = "An LXC declaration must create one unprivileged, stopped container and no VM."
  }
  assert {
    condition     = length(proxmox_virtual_environment_container.this[0].network_interface) == 1 && proxmox_virtual_environment_container.this[0].network_interface[0].bridge == "hsp100" && proxmox_virtual_environment_container.this[0].network_interface[0].firewall && proxmox_virtual_environment_container.this[0].initialization[0].ip_config[0].ipv4[0].address == "10.77.0.2/30" && proxmox_virtual_environment_container.this[0].initialization[0].ip_config[0].ipv4[0].gateway == "10.77.0.1"
    error_message = "The container must have exactly one enforced SDN interface with its assigned static address and gateway."
  }
  assert {
    condition     = proxmox_virtual_environment_container.this[0].initialization[0].user_account[0].keys == var.ssh_public_keys && proxmox_virtual_environment_container.this[0].operating_system[0].template_file_id == "local:vztmpl/debian-test.tar.zst" && proxmox_virtual_environment_container.this[0].operating_system[0].type == "debian"
    error_message = "Container creation must use the selected OS archive, managed distribution setup, and root SSH keys."
  }
  assert {
    condition     = !proxmox_virtual_environment_container.this[0].features[0].nesting && !proxmox_virtual_environment_container.this[0].features[0].keyctl && !proxmox_virtual_environment_container.this[0].features[0].fuse && !proxmox_virtual_environment_container.this[0].features[0].mknod && !proxmox_virtual_environment_container.this[0].delete_unreferenced_disks_on_destroy
    error_message = "Containers must not enable optional privilege-expanding features or deletion of unreferenced disks."
  }
  assert {
    condition = (
      proxmox_virtual_environment_firewall_options.this.container_id == 100 && proxmox_virtual_environment_firewall_options.this.vm_id == null &&
      proxmox_virtual_environment_firewall_ipset.this.container_id == 100 && proxmox_virtual_environment_firewall_ipset.this.vm_id == null &&
      proxmox_virtual_environment_firewall_rules.this.container_id == 100 && proxmox_virtual_environment_firewall_rules.this.vm_id == null
    )
    error_message = "All firewall resources must target the LXC API, never the QEMU VM API."
  }
  assert {
    condition     = alltrue([for r in proxmox_virtual_environment_firewall_rules.this.rule : r.iface == "net0"])
    error_message = "Container firewall rules must use Proxmox's net0 selector, not the internal eth0 name."
  }
  assert {
    condition     = proxmox_virtual_environment_firewall_options.this.enabled && proxmox_virtual_environment_firewall_options.this.input_policy == "DROP" && proxmox_virtual_environment_firewall_options.this.output_policy == "DROP" && proxmox_virtual_environment_firewall_options.this.macfilter && proxmox_virtual_environment_firewall_options.this.ipfilter && !proxmox_virtual_environment_firewall_options.this.dhcp && !proxmox_virtual_environment_firewall_options.this.ndp && proxmox_virtual_environment_firewall_ipset.this.cidr[0].name == "10.77.0.2" && output.rules[0].source == "::/0" && output.rules[0].action == "DROP" && output.rules[1].dest == "::/0" && output.rules[1].action == "DROP"
    error_message = "LXC must retain default DROP, anti-spoofing, and explicit IPv6 blocking."
  }
}

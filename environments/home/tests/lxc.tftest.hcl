mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  proxmox_api_token      = "terraform@pve!offline=offline-test-only"
  proxmox_endpoint       = "https://192.168.1.10:8006/"
  pihole_url             = "https://192.168.1.53"
  pihole_password        = "offline-test-only"
  node_name              = "pve"
  platform_cidr          = "10.77.0.0/24"
  host_address           = "192.168.1.10"
  protected_cidrs        = ["192.168.1.0/24"]
  bootstrap_admin_cidrs  = ["192.168.1.42/32"]
  dns_servers            = ["192.168.1.53"]
  ntp_servers            = []
  internet_egress_ports  = [{ protocol = "udp", port = 123 }]
  vm_template_id         = 9000
  lxc_template           = { file_id = "local:vztmpl/debian-test.tar.zst" }
  datastore_id           = "local-lvm"
  ssh_public_keys        = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  private_proxy_name     = "proxy"
  http_proxy_name        = "files"
  public_ports_lan_cidrs = ["192.168.1.0/24"]
  guests = {
    proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
    files = { type = "lxc", vm_id = 1001, slot = 1, vnet_id = "hsp1001", bootstrap = true, mount_points = [{ path = "/srv/data", size_gb = 50 }], dns = { files = { mode = "proxy", proxy_name = "proxy" }, files-host = { mode = "direct" } } }
    vpn   = { type = "lxc", vm_id = 1002, slot = 2, vnet_id = "hsp1002", role = "service_vpn", public_ports = [{ protocol = "udp", port = 51820 }] }
  }
  connections = [
    { from = "proxy", to = "files", protocol = "tcp", port = 8080 },
    { from = "files", to = "proxy", protocol = "tcp", port = 8443 },
  ]
}
run "mixed_guests_share_network_policy_and_dns" {
  command = plan
  assert {
    condition     = try(output.guests["files"].type == "lxc" && output.guests["vpn"].type == "lxc" && output.guests["proxy"].type == "vm", false)
    error_message = "Inventory types must select actual LXC creation while omitted types remain VMs."
  }
  assert {
    condition     = output.guests["files"].address == "10.77.0.6" && output.guests["vpn"].address == "10.77.0.10" && output.dns_targets["files"] == "10.77.0.2" && output.dns_targets["files-host"] == "10.77.0.6"
    error_message = "LXC guests must retain fixed-slot addresses and direct/proxy DNS behavior."
  }
  assert {
    condition     = contains([for r in output.policies["proxy"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.6/32:8080") && contains([for r in output.policies["files"] : "${r.type}:${coalesce(r.source, "-")}:${coalesce(r.dport, "-")}"], "in:10.77.0.2/32:8080") && contains([for r in output.policies["files"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.2/32:8443") && contains([for r in output.policies["proxy"] : "${r.type}:${coalesce(r.source, "-")}:${coalesce(r.dport, "-")}"], "in:10.77.0.6/32:8443")
    error_message = "VM-to-LXC and LXC-to-VM connections must receive paired egress/ingress rules."
  }
  assert {
    condition     = alltrue([for rules in values(output.policies) : toset([for r in rules : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["udp:123"])]) && contains([for r in output.policies["vpn"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.2/32:443")
    error_message = "LXC roles must inherit global NTP and narrow service-VPN proxy access without automatic web egress."
  }
  assert {
    condition     = contains([for r in output.policies["files"] : "${r.type}:${r.action}:${coalesce(r.source, "-")}:${coalesce(r.dport, "-")}"], "in:ACCEPT:192.168.1.42/32:22") && contains([for r in output.policies["vpn"] : "${r.type}:${r.action}:${coalesce(r.source, "-")}:${coalesce(r.proto, "-")}:${coalesce(r.dport, "-")}"], "in:ACCEPT:192.168.1.0/24:udp:51820") && contains([for r in output.policies["vpn"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.6/32:3128") && length([for r in output.policies["files"] : r if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == 0
    error_message = "LXC must inherit scoped bootstrap, LAN public ports and internal Squid access without opening Squid to the LAN."
  }
}
run "all_lxc_without_vm_template" {
  command = plan
  variables {
    vm_template_id       = null
    service_access_cidrs = ["192.168.1.0/24"]
    guests = {
      proxy = { type = "lxc", vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
      files = { type = "lxc", vm_id = 1001, slot = 1, vnet_id = "hsp1001" }
    }
    connections = []
  }
  assert {
    condition     = try(alltrue([for guest in values(output.guests) : guest.type == "lxc"]), false)
    error_message = "An LXC-only inventory must work without a VM template."
  }
  assert {
    condition     = toset([for r in output.policies["proxy"] : "${r.type}:${r.proto}:${r.dport}" if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == toset(["in:tcp:443"]) && length([for r in output.policies["files"] : r if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == 0
    error_message = "An LXC private proxy must receive only the selected LAN HTTPS exception."
  }
}
run "raw_lxc_mounts_require_host_ssh_through_inventory" {
  command = plan
  variables {
    guests = {
      proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
      files = {
        type       = "lxc", vm_id = 1001, slot = 1, vnet_id = "hsp1001"
        lxc_mounts = ["/dev/dri dev/dri none bind,optional,create=dir"]
      }
    }
    connections = []
  }
  expect_failures = [var.proxmox_ssh]
}
run "raw_lxc_configuration_through_inventory" {
  command = plan
  variables {
    proxmox_ssh = { host = "192.168.1.10", user = "root" }
    guests = {
      proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
      files = {
        type        = "lxc", vm_id = 1001, slot = 1, vnet_id = "hsp1001"
        lxc_mounts  = ["/dev/dri dev/dri none bind,optional,create=dir"]
        lxc_cgroups = { "devices.allow" = ["c 226:0 rwm", "c 226:128 rwm"] }
      }
    }
    connections = []
  }
  assert {
    condition     = output.guests["files"].type == "lxc" && output.guests["files"].address == "10.77.0.6"
    error_message = "Raw LXC configuration must work through the inventory without changing network identity."
  }
}
run "reject_lxc_missing_template" {
  command = plan
  variables { lxc_template = null }
  expect_failures = [var.lxc_template]
}
run "reject_vm_missing_template" {
  command = plan
  variables { vm_template_id = null }
  expect_failures = [var.vm_template_id]
}
run "reject_unknown_guest_type" {
  command = plan
  variables {
    guests          = { proxy = { type = "docker", vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" } }
    connections     = []
    http_proxy_name = null
  }
  expect_failures = [var.guests]
}
run "reject_cross_type_duplicate_id" {
  command = plan
  variables {
    guests = {
      proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
      files = { type = "lxc", vm_id = 1000, slot = 1, vnet_id = "hsp1001" }
    }
    connections = []
  }
  expect_failures = [var.guests]
}
run "reject_lxc_service_vpn_backend_access" {
  command = plan
  variables { connections = [{ from = "vpn", to = "files", protocol = "tcp", port = 8080 }] }
  expect_failures = [var.connections]
}
run "reject_cross_type_duplicate_slot" {
  command = plan
  variables {
    guests = {
      proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
      files = { type = "lxc", vm_id = 1001, slot = 0, vnet_id = "hsp1001" }
    }
    connections = []
  }
  expect_failures = [var.guests]
}

mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  proxmox_endpoint      = "https://192.168.1.10:8006/"
  pihole_url            = "https://192.168.1.53"
  pihole_password       = "offline-test-only"
  node_name             = "pve"
  platform_cidr         = "10.77.0.0/24"
  host_address          = "192.168.1.10"
  protected_cidrs       = ["192.168.1.0/24"]
  bootstrap_admin_cidrs = ["192.168.1.42/32"]
  dns_servers           = ["192.168.1.53"]
  ntp_servers           = ["192.168.1.1"]
  template_id           = 9000
  datastore_id          = "local-lvm"
  ssh_public_keys       = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  guests = {
    proxy = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "private_proxy" }
    cloud = { vm_id = 101, slot = 1, vnet_id = "hsp101", dns = { cloud = { mode = "proxy", proxy_name = "proxy" } } }
  }
  connections = [{ from = "proxy", to = "cloud", protocol = "tcp", port = 8080 }]
}
run "paired_rules_and_dns" {
  command = plan
  assert {
    condition     = output.guests["cloud"].address == "10.77.0.6" && output.guests["proxy"].address == "10.77.0.2"
    error_message = "Stable slots must produce the same addresses across modules."
  }
  assert {
    condition     = contains([for r in output.policies["proxy"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.6/32:8080") && contains([for r in output.policies["cloud"] : "${r.type}:${coalesce(r.source, "-")}:${coalesce(r.dport, "-")}"], "in:10.77.0.2/32:8080")
    error_message = "A declared connection needs both source egress and destination ingress."
  }
  assert {
    condition     = output.dns_targets["cloud"] == "10.77.0.2"
    error_message = "The application alias must resolve to its declared proxy."
  }
}
run "reject_duplicate_slots" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100" }, b = { vm_id = 101, slot = 0, vnet_id = "hsp101" } }
  }
  expect_failures = [var.guests]
}
run "reject_duplicate_ids" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100" }, b = { vm_id = 100, slot = 1, vnet_id = "hsp101" } }
  }
  expect_failures = [var.guests]
}
run "reject_duplicate_names" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100", dns = { clash = { mode = "direct" } } }, b = { vm_id = 101, slot = 1, vnet_id = "hsp101", dns = { clash = { mode = "direct" } } } }
  }
  expect_failures = [var.guests]
}
run "reject_vpn_to_admin" {
  command = plan
  variables {
    private_proxy_name = "proxy"
    guests             = { vpn = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "service_vpn" }, proxy = { vm_id = 101, slot = 1, vnet_id = "hsp101", role = "private_proxy" } }
    connections        = [{ from = "vpn", to = "proxy", protocol = "tcp", port = 22 }]
  }
  expect_failures = [var.connections]
}

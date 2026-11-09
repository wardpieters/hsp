mock_provider "system" { alias = "ingress" }
override_module {
  target = module.hsp.module.ipv6_ingress[0].module.teardown
}
mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  domain                = "home.example.com"
  proxmox_api_token     = "terraform@pve!offline=offline-test-only"
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
  vm_template_id        = 9000
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
  assert {
    condition     = alltrue(flatten([for rules in values(output.policies) : [for r in rules : !(r.action == "ACCEPT" && contains(var.bootstrap_admin_cidrs, coalesce(r.source, "-")))]]))
    error_message = "Omitting bootstrap must not grant administrator LAN access to guests."
  }
}

run "caller_forwards_ipv6_inventory_and_provider" {
  command = plan
  variables {
    proxmox_ssh           = { host = "192.0.2.10", user = "root" }
    internet_egress_ports = [{ protocol = "udp", port = 123 }]
    he_ipv6 = {
      enabled       = true
      server_ipv4   = "216.66.84.46"
      local_ipv4    = "192.168.1.10"
      client_ipv6   = "2001:470:1f14:4d4::2/64"
      server_ipv6   = "2001:470:1f14:4d4::1"
      routed_prefix = "2001:470:1f15:4d6::/64"
      ula_prefix    = "fd42:77:1::/48"
    }
  }
  assert {
    condition = (
      output.ipv6_ingress.public_address == "2001:470:1f15:4d6::2" &&
      output.ipv6_networks["proxy"].address == "fd42:77:1::2" &&
      output.ipv6_networks["cloud"].address == "fd42:77:1:1::2" &&
      length(output.ipv6_egress) == 2
    )
    error_message = "The caller must pass shared HE inputs and the SSH provider through to the platform module."
  }
}

# Local sources exercise this checkout. See ../README.md for standalone Git sources.
module "connections" {
  source                = "../../modules/connections"
  settings              = jsondecode(file(local.settings_file))
  require_api_endpoints = true
}

locals {
  # The templates keep validation/tests usable in a clean checkout.
  # Copy them to *.json and replace their values before deploying.
  settings_file = var.settings_file != null ? var.settings_file : (fileexists("${path.module}/../settings.json") ? "${path.module}/../settings.json" : "${path.module}/../settings.json.example")
  ipv6_file     = var.he_ipv6_file != null ? var.he_ipv6_file : (fileexists("${path.module}/../he-ipv6.json") ? "${path.module}/../he-ipv6.json" : "${path.module}/../he-ipv6.json.example")
  settings      = module.connections.settings
  he_ipv6       = jsondecode(file(local.ipv6_file))
}

module "hsp" {
  source = "../../modules/hsp"
  providers = {
    proxmox        = proxmox
    pihole         = pihole
    restful        = restful
    system.ingress = system.ingress
  }

  node_name             = "pve"
  platform_cidr         = local.settings.platform_cidr
  host_address          = local.settings.proxmox_ssh.host
  protected_cidrs       = ["192.0.2.0/24"]
  bootstrap_admin_cidrs = ["192.0.2.42/32"]
  dns_servers           = ["192.0.2.53"]
  ntp_servers           = []
  domain                = "home.example.com"
  vm_template_id        = 9000
  datastore_id          = "local-lvm"
  ssh_public_keys       = var.ssh_public_keys
  proxmox_ssh           = local.settings.proxmox_ssh
  he_ipv6               = local.he_ipv6
  private_proxy_name    = "proxy"

  # New guests remain stopped; configure their software after inspection.
  guests = {
    proxy = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "private_proxy" }
    app = {
      vm_id = 1001, slot = 1, vnet_id = "hsp1001"
      dns   = { app = { mode = "proxy", proxy_name = "proxy" } }
    }
  }
  connections = [{ from = "proxy", to = "app", protocol = "tcp", port = 8080 }]
}

output "guests" {
  value = module.hsp.guests
}

output "router_route" {
  value = module.hsp.router_route
}

output "public_forwards" {
  value = module.hsp.public_forwards
}

output "host_policy" {
  value     = module.hsp.host_policy
  sensitive = true
}

output "policies" {
  value     = module.hsp.policies
  sensitive = true
}

output "dns_targets" {
  value = module.hsp.dns_targets
}

output "ipv6_ingress" {
  value = module.hsp.ipv6_ingress
}

output "ipv6_networks" {
  value = module.hsp.ipv6_networks
}

output "ipv6_port_forwards" {
  value = module.hsp.ipv6_port_forwards
}

output "ipv6_egress" {
  value = module.hsp.ipv6_egress
}

output "ipv6_host_requirements" {
  value = module.hsp.ipv6_host_requirements
}

output "ipv6_hairpin" {
  value = module.hsp.ipv6_hairpin
}

# Local sources exercise this checkout. See ../README.md for standalone Git sources.
module "connections" {
  source   = "../../modules/connections"
  settings = jsondecode(file(local.settings_file))
}

locals {
  # The templates keep validation/tests usable in a clean checkout.
  # Copy them to *.json and replace their values before deploying.
  settings_file = var.settings_file != null ? var.settings_file : (fileexists("${path.module}/../settings.json") ? "${path.module}/../settings.json" : "${path.module}/../settings.json.example")
  ipv6_file     = var.he_ipv6_file != null ? var.he_ipv6_file : (fileexists("${path.module}/../he-ipv6.json") ? "${path.module}/../he-ipv6.json" : "${path.module}/../he-ipv6.json.example")
  settings      = module.connections.settings
  he_ipv6       = jsondecode(file(local.ipv6_file))
}

module "proxmox" {
  source        = "../../modules/proxmox_host"
  providers     = { system = system.proxmox }
  platform_cidr = local.settings.platform_cidr
  proxmox_ssh   = local.settings.proxmox_ssh
  he_ipv6       = coalesce(tobool(try(local.he_ipv6.enabled, null)), false) ? local.he_ipv6 : null
}

output "he_ipv6_status" { value = module.proxmox.he_ipv6_status }

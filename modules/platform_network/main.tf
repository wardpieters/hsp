variable "platform_cidr" {
  type = string
  validation {
    condition = try(
      cidrhost(var.platform_cidr, 0) == split("/", var.platform_cidr)[0] &&
      tonumber(split("/", var.platform_cidr)[1]) <= 30 && (
        (can(regex("^10\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 8) ||
        (can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 12) ||
        (can(regex("^192\\.168\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 16)
    ), false)
    error_message = "platform_cidr must be a canonical RFC1918 IPv4 network with prefix <= 30."
  }
}
variable "node_name" { type = string }
variable "zone_id" {
  type    = string
  default = "hsp"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,7}$", var.zone_id))
    error_message = "zone_id must be at most eight alphanumeric characters, starting with a letter."
  }
}
variable "protected_cidrs" {
  type = list(string)
  validation {
    condition = alltrue([for c in var.protected_cidrs : try(
      cidrnetmask(c) != "" &&
      cidrhost("${split("/", c)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0) !=
    cidrhost("${split("/", var.platform_cidr)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0), false)])
    error_message = "Protected IPv4 networks must not overlap the platform aggregate."
  }
}
variable "networks" {
  type    = map(object({ slot = number, vnet_id = string, ipv6_cidr = optional(string) }))
  default = {}
  validation {
    condition     = length(distinct([for n in values(var.networks) : n.slot])) == length(var.networks) && length(distinct([for n in values(var.networks) : n.vnet_id])) == length(var.networks)
    error_message = "Every guest needs a unique subnet slot and VNet ID."
  }
  validation {
    condition     = length(distinct([for n in values(var.networks) : n.ipv6_cidr if n.ipv6_cidr != null])) == length([for n in values(var.networks) : n.ipv6_cidr if n.ipv6_cidr != null])
    error_message = "IPv6 subnets must be unique across isolated VNets."
  }
}

# Created first and destroyed last: apply the removal of SDN objects too.
resource "proxmox_sdn_applier" "finalizer" {
  on_create  = false
  on_destroy = true
}
resource "proxmox_sdn_zone_simple" "this" {
  id         = var.zone_id
  nodes      = [var.node_name]
  ipam       = "pve"
  depends_on = [proxmox_sdn_applier.finalizer]
}
module "guest" {
  for_each      = var.networks
  source        = "../guest_network"
  platform_cidr = var.platform_cidr
  slot          = each.value.slot
  zone_id       = proxmox_sdn_zone_simple.this.id
  vnet_id       = each.value.vnet_id
  ipv6_cidr     = each.value.ipv6_cidr
}
resource "terraform_data" "generation" {
  input = merge({
    cidr               = var.platform_cidr, zone = var.zone_id, node = var.node_name,
    networks           = { for name, n in var.networks : name => { slot = n.slot, vnet_id = n.vnet_id } },
    resource_revisions = { for name, guest in module.guest : name => guest.revision }
    }, anytrue([for n in values(var.networks) : n.ipv6_cidr != null]) ? {
    ipv6_networks = { for name, n in var.networks : name => n.ipv6_cidr if n.ipv6_cidr != null }
  } : {})
  lifecycle { replace_triggered_by = [proxmox_sdn_zone_simple.this] }
}
# The provider labels the applier experimental; the SDN and packet filtering
# facilities themselves are the existing native Proxmox services.
resource "proxmox_sdn_applier" "apply" {
  on_create  = true
  on_destroy = false
  depends_on = [module.guest, proxmox_sdn_zone_simple.this]
  lifecycle { replace_triggered_by = [terraform_data.generation] }
}
output "networks" {
  value = { for name, n in module.guest : name => {
    cidr = n.cidr, gateway = n.gateway, address = n.address, vnet_id = n.vnet_id, ipv6 = n.ipv6
  } }
  depends_on = [proxmox_sdn_applier.apply]
}
output "zone_id" { value = proxmox_sdn_zone_simple.this.id }
output "route_cidr" { value = var.platform_cidr }

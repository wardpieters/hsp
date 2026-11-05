variable "platform_cidr" {
  type = string
  validation {
    condition     = try(cidrnetmask(var.platform_cidr) != "" && tonumber(split("/", var.platform_cidr)[1]) <= 30, false)
    error_message = "platform_cidr must be an IPv4 CIDR with room for a /30."
  }
}

variable "slot" {
  type = number
  validation {
    condition     = try(var.slot >= 0 && floor(var.slot) == var.slot && var.slot < pow(2, 30 - tonumber(split("/", var.platform_cidr)[1])), false)
    error_message = "slot must be a non-negative integer within the platform aggregate."
  }
}

variable "zone_id" { type = string }
variable "ipv6_cidr" {
  type    = string
  default = null
  validation {
    condition = var.ipv6_cidr == null ? true : try(
      strcontains(var.ipv6_cidr, ":") && split("/", var.ipv6_cidr)[1] == "64" &&
      cidrhost(var.ipv6_cidr, 0) == split("/", var.ipv6_cidr)[0] &&
    cidrhost("${split("/", var.ipv6_cidr)[0]}/8", 0) == "fd00::", false)
    error_message = "ipv6_cidr must be a canonical ULA /64 or null."
  }
}
variable "vnet_id" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,7}$", var.vnet_id))
    error_message = "VNet IDs must start with a letter and contain at most eight alphanumeric characters."
  }
}

locals {
  # try keeps an invalid slot's validation error clear instead of raising an expression error.
  cidr    = try(cidrsubnet(var.platform_cidr, 30 - tonumber(split("/", var.platform_cidr)[1]), var.slot), "10.0.0.0/30")
  gateway = cidrhost(local.cidr, 1)
  address = cidrhost(local.cidr, 2)
}

resource "proxmox_sdn_vnet" "this" {
  id            = var.vnet_id
  zone          = var.zone_id
  vlan_aware    = false
  isolate_ports = true
}

resource "proxmox_sdn_subnet" "this" {
  vnet    = proxmox_sdn_vnet.this.id
  cidr    = local.cidr
  gateway = local.gateway
  snat    = true
}

resource "terraform_data" "revision" {
  lifecycle {
    replace_triggered_by = [proxmox_sdn_vnet.this, proxmox_sdn_subnet.this]
  }
}

resource "proxmox_sdn_subnet" "ipv6" {
  count   = var.ipv6_cidr == null ? 0 : 1
  vnet    = proxmox_sdn_vnet.this.id
  cidr    = var.ipv6_cidr
  gateway = cidrhost(var.ipv6_cidr, 1)
  snat    = false
}
output "ipv6" {
  value = var.ipv6_cidr == null ? null : {
    cidr = var.ipv6_cidr, gateway = cidrhost(var.ipv6_cidr, 1), address = cidrhost(var.ipv6_cidr, 2)
  }
}

output "cidr" { value = local.cidr }
output "gateway" { value = local.gateway }
output "address" { value = local.address }
output "vnet_id" { value = proxmox_sdn_vnet.this.id }
resource "terraform_data" "ipv6_revision" {
  count = var.ipv6_cidr == null ? 0 : 1
  lifecycle { replace_triggered_by = [proxmox_sdn_subnet.ipv6[count.index]] }
}
output "revision" {
  value = var.ipv6_cidr == null ? terraform_data.revision.id : sha256(jsonencode([terraform_data.revision.id, terraform_data.ipv6_revision[0].id]))
}

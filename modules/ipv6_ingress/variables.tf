variable "public_address" {
  type = string
  validation {
    condition     = try(cidrhost("${var.public_address}/128", 0) == var.public_address && cidrhost("${var.public_address}/3", 0) == "2000::", false)
    error_message = "public_address must be a canonical global IPv6 host address."
  }
}
variable "ula_prefix" {
  type = string
  validation {
    condition     = try(split("/", var.ula_prefix)[1] == "48" && cidrhost(var.ula_prefix, 0) == split("/", var.ula_prefix)[0] && cidrhost("${split("/", var.ula_prefix)[0]}/8", 0) == "fd00::", false)
    error_message = "ula_prefix must be a canonical fd00::/8 /48."
  }
}
variable "protected_cidrs" {
  type    = list(string)
  default = []
  validation {
    condition     = alltrue([for c in var.protected_cidrs : try(strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "Protected ranges must be canonical IPv6 CIDRs."
  }
}
variable "firewall_bridges" {
  description = "Exact legacy Proxmox net0 firewall bridges mapped to their participating guest ULA. Bridge tracking uses zone 1; routed IPv6 NAT uses zone 0."
  type        = map(string)
  default     = {}
  validation {
    condition = try(length(distinct(values(var.firewall_bridges))) == length(var.firewall_bridges) && alltrue([for bridge, address in var.firewall_bridges :
      can(regex("^fwbr[0-9]{1,9}i0$", bridge)) && contains(concat([for f in values(var.forwards) : f.address], [for e in values(var.egress) : e.address]), address)
    ]), false)
    error_message = "firewall_bridges must map exact net0 bridge names to distinct participating guest ULA addresses, never wildcards or unrelated interfaces."
  }
}
variable "forwards" {
  type    = map(object({ guest = string, port = number, address = string, vnet_id = string }))
  default = {}
  validation {
    condition = try(length(distinct([for f in values(var.forwards) : f.port])) == length(var.forwards) && alltrue([for f in values(var.forwards) :
      cidrhost("${f.address}/128", 0) == f.address && cidrhost("${f.address}/48", 0) == cidrhost(var.ula_prefix, 0) &&
      can(regex("^[A-Za-z][A-Za-z0-9]{0,7}$", f.vnet_id)) && can(regex("^[a-z][a-z0-9-]{0,62}$", f.guest)) &&
      floor(f.port) == f.port && f.port >= 1 && f.port <= 65535 && !contains([22, 8006], f.port)
    ]), false)
    error_message = "Forward targets need exact ULA hosts, valid VNets/guest names and unique non-management TCP ports."
  }
}
variable "egress" {
  type    = map(object({ address = string, vnet_id = string, ports = list(object({ protocol = string, port = optional(number) })) }))
  default = {}
  validation {
    condition = try(alltrue([for e in values(var.egress) :
      cidrhost("${e.address}/128", 0) == e.address && cidrhost("${e.address}/48", 0) == cidrhost(var.ula_prefix, 0) &&
      can(regex("^[A-Za-z][A-Za-z0-9]{0,7}$", e.vnet_id)) && length(e.ports) > 0 &&
      alltrue([for p in e.ports : p.protocol == "icmp" ? p.port == null : contains(["tcp", "udp"], p.protocol) && floor(p.port) == p.port && p.port >= 1 && p.port <= 65535])
    ]), false)
    error_message = "Egress needs exact ULA hosts/VNets and TCP/UDP destination ports or portless ICMP."
  }
}

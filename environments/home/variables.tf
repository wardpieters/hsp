variable "proxmox_endpoint" {
  type = string
  validation {
    condition     = can(regex("^https://[^/@?#]+/?$", var.proxmox_endpoint))
    error_message = "Use the HTTPS Proxmox endpoint without embedded credentials or a path."
  }
}
variable "proxmox_insecure_tls" {
  description = "Skip TLS certificate verification for the Proxmox API."
  type        = bool
  default     = false
}
variable "pihole_url" {
  type = string
  validation {
    condition     = can(regex("^https://[^/@?#]+/?$", var.pihole_url))
    error_message = "Use Pi-hole's HTTPS endpoint."
  }
}
variable "pihole_insecure_tls" {
  description = "Skip TLS certificate verification for the Pi-hole API."
  type        = bool
  default     = false
}
variable "pihole_password" {
  type      = string
  sensitive = true
}
variable "node_name" { type = string }
variable "platform_cidr" { type = string }
variable "host_address" {
  type = string
  validation {
    condition = can(cidrnetmask("${var.host_address}/32")) && anytrue([for c in var.protected_cidrs : try(
    cidrhost("${var.host_address}/${split("/", c)[1]}", 0) == cidrhost(c, 0), false)])
    error_message = "host_address must be an IPv4 address inside a declared protected LAN network."
  }
}
variable "protected_cidrs" {
  description = "All real LAN, existing guest, management and VPN networks; must not overlap platform_cidr."
  type        = list(string)
  validation {
    condition     = length(var.protected_cidrs) > 0
    error_message = "Declare the actual protected networks before provisioning."
  }
}
variable "bootstrap_admin_cidrs" {
  description = "Administrator IPv4 /32 sources for guest bootstrap SSH and, when managed, Proxmox host access."
  type        = list(string)
  validation {
    condition     = alltrue([for c in var.bootstrap_admin_cidrs : try(cidrnetmask(c) != "" && split("/", c)[1] == "32", false)])
    error_message = "Bootstrap management access must name individual IPv4 /32 addresses."
  }
}
variable "manage_host_firewall" {
  description = "Opt in after reviewing/importing the existing full node ruleset. Otherwise configure equivalent host protection before starting guests."
  type        = bool
  default     = false
}
variable "dns_servers" { type = list(string) }
variable "ntp_servers" { type = list(string) }
variable "template_id" { type = number }
variable "datastore_id" { type = string }
variable "ssh_public_keys" { type = list(string) }
variable "private_proxy_name" {
  type    = string
  default = null
  validation {
    condition     = alltrue([for g in values(var.guests) : g.role != "service_vpn"]) || try(var.guests[var.private_proxy_name].role == "private_proxy", false)
    error_message = "Service VPN guests require a named private_proxy target."
  }
}
variable "guests" {
  type = map(object({
    vm_id         = number, slot = number, vnet_id = string, role = optional(string, "workload"),
    started       = optional(bool, false), on_boot = optional(bool, false),
    bootstrap     = optional(bool, false),
    cores         = optional(number, 2), memory_mb = optional(number, 2048), disk_gb = optional(number, 16),
    backup        = optional(bool, true),
    allow_updates = optional(bool, false),
    public_ports  = optional(list(object({ protocol = string, port = number })), []),
    dns           = optional(map(object({ mode = string, proxy_name = optional(string), proxy_address = optional(string) })), {})
  }))
  validation {
    condition = (
      length(distinct([for g in values(var.guests) : g.vm_id])) == length(var.guests) &&
      length(distinct([for g in values(var.guests) : g.slot])) == length(var.guests) &&
      length(distinct([for g in values(var.guests) : g.vnet_id])) == length(var.guests) &&
      length(distinct(flatten([for g in values(var.guests) : keys(g.dns)]))) == length(flatten([for g in values(var.guests) : keys(g.dns)])) &&
      alltrue([for name, g in var.guests : can(regex("^[a-z][a-z0-9-]{0,62}$", name)) &&
        contains(["workload", "public_proxy", "private_proxy", "admin_vpn", "service_vpn", "management"], g.role) &&
      (!contains(["private_proxy", "management"], g.role) || length(g.public_ports) == 0)])
    )
    error_message = "Guest names/roles must be valid, VM IDs/slots/VNets/DNS aliases unique, and private/management guests cannot expose public ports."
  }
  validation {
    condition = alltrue(flatten([for g in values(var.guests) : [for d in values(g.dns) : d.mode != "proxy" || try(
      (d.proxy_name != null && d.proxy_address == null && contains(["public_proxy", "private_proxy"], var.guests[d.proxy_name].role)) ||
    (d.proxy_name == null && can(cidrnetmask("${d.proxy_address}/32"))), false)]]))
    error_message = "Proxy DNS aliases need either a declared proxy guest or an explicit external proxy address."
  }
}
variable "connections" {
  description = "Allowed guest-to-guest service dependencies; creates both egress and ingress."
  type        = list(object({ from = string, to = string, protocol = string, port = number }))
  default     = []
  validation {
    condition = alltrue([for c in var.connections : try(
      c.from != c.to && contains(keys(var.guests), c.from) && contains(keys(var.guests), c.to) &&
      contains(["tcp", "udp"], c.protocol) && c.port >= 1 && c.port <= 65535 && floor(c.port) == c.port &&
    (var.guests[c.from].role != "service_vpn" || (c.to == var.private_proxy_name && c.protocol == "tcp" && c.port == 443)), false)])
    error_message = "Connections require existing distinct peers and numeric ports; the service VPN may reach only its private proxy over TCP 443."
  }
}

variable "proxmox_api_token" {
  description = "Shared non-root Proxmox API token (user@realm!tokenid=secret). Supply through TF_VAR_proxmox_api_token."
  type        = string
  sensitive   = true
  ephemeral   = true
  nullable    = false
  validation {
    condition     = can(regex("^[^[:space:]!]+![^[:space:]=]+=[^[:space:]]+$", var.proxmox_api_token))
    error_message = "Supply a Proxmox API token as user@realm!tokenid=secret through TF_VAR_proxmox_api_token."
  }
}
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
variable "proxmox_ssh" {
  description = "Optional Proxmox host SSH agent connection, required only for raw LXC mounts/cgroups; non-root users need passwordless sudo."
  type        = object({ host = string, user = string, port = optional(number, 22), host_key = optional(string) })
  default     = null
  validation {
    condition     = var.proxmox_ssh != null || alltrue([for guest in values(var.guests) : length(guest.lxc_mounts) == 0 && length(guest.lxc_cgroups) == 0])
    error_message = "Guests with lxc_mounts/lxc_cgroups require proxmox_ssh with host and user."
  }
}
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
variable "public_ports_lan_cidrs" {
  description = "LAN IPv4 subnets allowed to reach each guest's declared public_ports."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition = alltrue([for c in var.public_ports_lan_cidrs : try(
      cidrnetmask(c) != "" && cidrhost(c, 0) == split("/", c)[0] && tonumber(split("/", c)[1]) > 0 &&
      cidrhost("${split("/", c)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0) !=
    cidrhost("${split("/", var.platform_cidr)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0), false)])
    error_message = "Public-port LAN sources must be canonical IPv4 CIDRs, narrower than /0, and must not overlap platform_cidr."
  }
}
variable "service_access_cidrs" {
  description = "LAN IPv4 subnets allowed to reach the selected private proxy on TCP 443."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition = alltrue([for c in var.service_access_cidrs : try(
      cidrnetmask(c) != "" && cidrhost(c, 0) == split("/", c)[0] && tonumber(split("/", c)[1]) > 0 &&
      cidrhost("${split("/", c)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0) !=
    cidrhost("${split("/", var.platform_cidr)[0]}/${min(tonumber(split("/", c)[1]), tonumber(split("/", var.platform_cidr)[1]))}", 0), false)])
    error_message = "Service-access sources must be canonical IPv4 CIDRs, narrower than /0, and must not overlap platform_cidr."
  }
}
variable "manage_host_firewall" {
  description = "Opt in after reviewing/importing the existing full node ruleset. Otherwise configure equivalent host protection before starting guests."
  type        = bool
  default     = false
}
variable "dns_servers" { type = list(string) }
variable "domain" {
  description = "DNS domain appended to guest record names."
  type        = string
  nullable    = false
}
variable "ntp_servers" { type = list(string) }
variable "internet_egress_ports" {
  description = "Outbound TCP/UDP destination ports allowed for every VM and LXC, combined with each guest's internet_egress_ports and role defaults (monitoring adds TCP 80/443)."
  type        = list(object({ protocol = string, port = number }))
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for p in var.internet_egress_ports : try(contains(["tcp", "udp"], p.protocol) && p.port >= 1 && p.port <= 65535 && floor(p.port) == p.port, false)])
    error_message = "Global internet egress ports require TCP/UDP and an integer destination port from 1 to 65535."
  }
}
variable "vm_template_id" {
  description = "Cloud-init VM template ID, required when any VM guest is declared."
  type        = number
  default     = null
  validation {
    condition     = alltrue([for g in values(var.guests) : g.type != "vm"]) || try(var.vm_template_id >= 100 && var.vm_template_id <= 999999999 && floor(var.vm_template_id) == var.vm_template_id, false)
    error_message = "VM guests require a valid vm_template_id. Rename the former template_id input."
  }
}
variable "lxc_template" {
  description = "Downloaded Proxmox OS archive used by every LXC guest; os_type defaults to debian."
  type        = object({ file_id = string, os_type = optional(string, "debian") })
  default     = null
  validation {
    condition     = alltrue([for g in values(var.guests) : g.type != "lxc"]) || var.lxc_template != null
    error_message = "LXC guests require the global lxc_template with a downloaded storage:vztmpl/archive file_id."
  }
}
variable "datastore_id" { type = string }
variable "ssh_public_keys" { type = list(string) }
variable "http_proxy_name" {
  description = "Optional HTTP forward-proxy guest that every other guest may reach on TCP 3128."
  type        = string
  default     = null
  validation {
    condition     = var.http_proxy_name == null ? true : contains(keys(var.guests), var.http_proxy_name)
    error_message = "http_proxy_name must name a declared guest or be null."
  }
}
variable "private_proxy_name" {
  type    = string
  default = null
  validation {
    condition     = (length(var.service_access_cidrs) == 0 && alltrue([for g in values(var.guests) : g.role != "service_vpn"])) || try(var.guests[var.private_proxy_name].role == "private_proxy", false)
    error_message = "Service VPN guests and LAN service access require a named private_proxy target."
  }
}
variable "guests" {
  type = map(object({
    vm_id                 = number, slot = number, vnet_id = string, role = optional(string, "workload"),
    type                  = optional(string, "vm"),
    nesting               = optional(bool, false),
    lxc_mounts            = optional(list(string), []),
    lxc_cgroups           = optional(map(list(string)), {}),
    started               = optional(bool, false), on_boot = optional(bool, false),
    bootstrap             = optional(bool, false),
    cores                 = optional(number, 2), memory_mb = optional(number, 2048), disk_gb = optional(number, 16),
    backup                = optional(bool, true),
    ssd                   = optional(bool, false),
    extra_disks           = optional(map(object({ size_gb = number, datastore_id = optional(string), backup = optional(bool, true), ssd = optional(bool, false) })), {}),
    mount_points          = optional(list(object({ path = string, size_gb = number, datastore_id = optional(string), backup = optional(bool, true) })), []),
    internet_egress_ports = optional(list(object({ protocol = string, port = number })), []),
    public_ports          = optional(list(object({ protocol = string, port = number })), []),
    dns                   = optional(map(object({ mode = string, proxy_name = optional(string), proxy_address = optional(string) })), {})
  }))
  validation {
    condition = (
      length(distinct([for g in values(var.guests) : g.vm_id])) == length(var.guests) &&
      length(distinct([for g in values(var.guests) : g.slot])) == length(var.guests) &&
      length(distinct([for g in values(var.guests) : g.vnet_id])) == length(var.guests) &&
      length(distinct(flatten([for g in values(var.guests) : keys(g.dns)]))) == length(flatten([for g in values(var.guests) : keys(g.dns)])) &&
      alltrue([for name, g in var.guests : can(regex("^[a-z][a-z0-9-]{0,62}$", name)) &&
        contains(["vm", "lxc"], g.type) &&
        contains(["workload", "public_proxy", "private_proxy", "admin_vpn", "service_vpn", "management", "monitoring"], g.role) &&
      (!contains(["private_proxy", "management"], g.role) || length(g.public_ports) == 0)])
    )
    error_message = "Guest names/types/roles must be valid, VM/LXC IDs/slots/VNets/DNS aliases unique, and private/management guests cannot expose public ports."
  }
  validation {
    condition = alltrue(flatten([for g in values(var.guests) : [for d in values(g.dns) : d.mode != "proxy" || try(
      (d.proxy_name != null && d.proxy_address == null && contains(["public_proxy", "private_proxy"], var.guests[d.proxy_name].role)) ||
    (d.proxy_name == null && can(cidrnetmask("${d.proxy_address}/32"))), false)]]))
    error_message = "Proxy DNS aliases need either a declared proxy guest or an explicit external proxy address."
  }
}
variable "connections" {
  description = "Connections between guests (paired rules), from a guest to an external bare IPv4 address (egress only), or from an external IPv4 host with an optional /32 suffix to a guest (ingress only). External addresses must be outside platform_cidr."
  type        = list(object({ from = string, to = string, protocol = string, port = number }))
  default     = []
  validation {
    condition = alltrue([for c in var.connections : try(
      c.from != c.to &&
      (contains(keys(var.guests), c.from) || (contains(keys(var.guests), c.to) && try(
        can(cidrnetmask("${trimsuffix(c.from, "/32")}/32")) &&
      cidrhost("${trimsuffix(c.from, "/32")}/${split("/", var.platform_cidr)[1]}", 0) != cidrhost(var.platform_cidr, 0), false))) &&
      (contains(keys(var.guests), c.to) || try(
        can(cidrnetmask("${c.to}/32")) &&
      cidrhost("${c.to}/${split("/", var.platform_cidr)[1]}", 0) != cidrhost(var.platform_cidr, 0), false)) &&
    contains(["tcp", "udp"], c.protocol) && c.port >= 1 && c.port <= 65535 && floor(c.port) == c.port, false)])
    error_message = "Connections require at least one declared guest, different endpoints, TCP/UDP, and an integer port from 1 to 65535. External IPv4 addresses must be outside platform_cidr; sources allow an optional /32 suffix and destinations must be bare addresses."
  }
  validation {
    condition = alltrue([for c in var.connections : try(
      try(var.guests[c.from].role, null) != "service_vpn" ||
      (c.to == var.private_proxy_name && c.protocol == "tcp" && c.port == 443) ||
    (c.to == var.http_proxy_name && c.protocol == "tcp" && c.port == 3128), false)])
    error_message = "The service VPN may reach only its private proxy over TCP 443 and the selected HTTP proxy over TCP 3128."
  }
}

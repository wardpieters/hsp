variable "name" { type = string }
variable "node_name" { type = string }
variable "vm_id" {
  type = number
  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999 && floor(var.vm_id) == var.vm_id
    error_message = "vm_id must be an integer in Proxmox's guest ID range."
  }
}
variable "guest_type" {
  type    = string
  default = "vm"
  validation {
    condition     = contains(["vm", "lxc"], var.guest_type)
    error_message = "guest_type must be vm or lxc."
  }
}
variable "vm_template_id" {
  type    = number
  default = null
  validation {
    condition     = var.guest_type != "vm" || try(var.vm_template_id >= 100 && var.vm_template_id <= 999999999 && floor(var.vm_template_id) == var.vm_template_id, false)
    error_message = "VM guests require a valid vm_template_id."
  }
}
variable "nesting" {
  description = "Enable Proxmox nesting for this LXC container."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.nesting || var.guest_type == "lxc"
    error_message = "nesting can only be enabled for LXC guests."
  }
}
variable "lxc_template" {
  type    = object({ file_id = string, os_type = optional(string, "debian") })
  default = null
  validation {
    condition = var.guest_type != "lxc" || try(
      can(regex("^[A-Za-z][A-Za-z0-9_-]*:vztmpl/[^/[:space:]]+$", var.lxc_template.file_id)) &&
    contains(["alpine", "archlinux", "centos", "debian", "devuan", "fedora", "gentoo", "nixos", "opensuse", "ubuntu"], var.lxc_template.os_type), false)
    error_message = "LXC guests require lxc_template with a storage:vztmpl/archive file_id and a supported managed os_type."
  }
}
variable "datastore_id" {
  type = string
  validation {
    condition     = var.guest_type != "lxc" || can(regex("^[A-Za-z][A-Za-z0-9_-]*$", var.datastore_id))
    error_message = "LXC datastore_id must be a storage ID, never a host path or existing volume reference."
  }
}
variable "mount_points" {
  description = "Ordered LXC-managed volumes, sized in GiB and mounted at absolute container paths. Append entries to preserve mp indexes."
  type        = list(object({ path = string, size_gb = number, datastore_id = optional(string), backup = optional(bool, true) }))
  default     = []
  nullable    = false
  validation {
    condition = try(
      (var.guest_type == "lxc" || length(var.mount_points) == 0) && length(var.mount_points) <= 256 &&
      length(distinct([for m in var.mount_points : m.path])) == length(var.mount_points) &&
      alltrue([for m in var.mount_points :
        can(regex("^/[^[:space:],=\\\\]+$", m.path)) && alltrue([for part in split("/", trimprefix(m.path, "/")) : part != "" && !contains([".", ".."], part)]) &&
        m.size_gb > 0 && floor(m.size_gb) == m.size_gb &&
    (m.datastore_id == null || can(regex("^[A-Za-z][A-Za-z0-9_-]*$", m.datastore_id)))]), false)
    error_message = "Mount points are LXC-only: use unique normalized absolute non-root paths without whitespace, commas, equals or backslashes; positive integer sizes in GiB; and storage IDs instead of host paths or existing volumes."
  }
}
variable "network" {
  type = object({ address = string, gateway = string, cidr = string, vnet_id = string })
  validation {
    condition = try(tonumber(split("/", var.network.cidr)[1]) == 30 &&
    cidrhost(var.network.cidr, 1) == var.network.gateway && cidrhost(var.network.cidr, 2) == var.network.address, false)
    error_message = "network must be a /30 with gateway at offset 1 and guest at offset 2."
  }
}
variable "started" {
  description = "Set true in a second apply after inspecting the stopped VM and verifying firewall enforcement."
  type        = bool
  default     = false
}
variable "on_boot" {
  type    = bool
  default = false
  validation {
    condition     = !var.on_boot || var.started
    error_message = "Autostart requires explicit activation."
  }
}
variable "cores" {
  type    = number
  default = 2
}
variable "memory_mb" {
  type    = number
  default = 2048
}
variable "disk_gb" {
  type    = number
  default = 16
}
variable "backup" {
  description = "Include the managed VM disk in Proxmox backups."
  type        = bool
  default     = true
  validation {
    condition     = var.guest_type != "lxc" || var.backup
    error_message = "LXC root filesystems have no backup toggle. Omit backup=false and exclude the container in your backup job instead; configure mount backups per mount_point."
  }
}
variable "ssh_public_keys" {
  type = list(string)
  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for k in var.ssh_public_keys : can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) [A-Za-z0-9+/=]+", k))])
    error_message = "Supply at least one SSH public key; passwords/private keys do not belong in cloud-init."
  }
}
variable "username" {
  type    = string
  default = "ward"
}
variable "dns_servers" {
  type = list(string)
  validation {
    condition     = length(var.dns_servers) > 0 && alltrue([for ip in var.dns_servers : can(cidrnetmask("${ip}/32"))])
    error_message = "Supply approved IPv4 resolver addresses."
  }
}
variable "ntp_servers" {
  type = list(string)
  validation {
    condition     = alltrue([for ip in var.ntp_servers : can(cidrnetmask("${ip}/32"))])
    error_message = "NTP targets must be explicit IPv4 addresses."
  }
}
variable "protected_cidrs" {
  type = list(string)
  validation {
    condition     = alltrue([for c in var.protected_cidrs : can(cidrnetmask(c))])
    error_message = "protected_cidrs must contain IPv4 networks."
  }
}
variable "internet_egress_ports" {
  description = "Outbound TCP/UDP destination ports allowed outside protected networks. Defaults to no internet egress."
  type        = list(object({ protocol = string, port = number }))
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for p in var.internet_egress_ports : try(contains(["tcp", "udp"], p.protocol) && p.port >= 1 && p.port <= 65535 && floor(p.port) == p.port, false)])
    error_message = "Internet egress ports require TCP/UDP and an integer destination port from 1 to 65535."
  }
}
variable "public_ports_lan_cidrs" {
  description = "LAN IPv4 subnets allowed to reach this VM's declared public_ports before protected-source drops."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for c in var.public_ports_lan_cidrs : try(cidrnetmask(c) != "" && cidrhost(c, 0) == split("/", c)[0] && tonumber(split("/", c)[1]) > 0, false)])
    error_message = "Public-port LAN sources must be canonical IPv4 CIDRs narrower than /0."
  }
}
variable "service_access_cidrs" {
  description = "LAN IPv4 subnets allowed to reach this VM on TCP 443 before protected-source drops."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for c in var.service_access_cidrs : try(cidrnetmask(c) != "" && cidrhost(c, 0) == split("/", c)[0] && tonumber(split("/", c)[1]) > 0, false)])
    error_message = "Service-access sources must be canonical IPv4 CIDRs narrower than /0."
  }
}
variable "public_ports" {
  type    = list(object({ protocol = string, port = number }))
  default = []
  validation {
    condition     = alltrue([for p in var.public_ports : contains(["tcp", "udp"], p.protocol) && p.port >= 1 && p.port <= 65535 && floor(p.port) == p.port && !contains([22, 8006], p.port)])
    error_message = "Public ports require TCP/UDP and a numeric port; management ports 22 and 8006 are excluded."
  }
}
variable "allow_rules" {
  type = list(object({
    direction = string, address = string, protocol = string, ports = string, description = string
  }))
  default = []
  validation {
    condition = alltrue([for r in var.allow_rules : try(
      contains(["in", "out"], r.direction) && contains(["tcp", "udp"], r.protocol) &&
      can(cidrnetmask(r.address)) && tonumber(split("/", r.address)[1]) == 32 &&
      can(regex("^[0-9]+([,:][0-9]+)*$", r.ports)) &&
    alltrue([for p in split(",", replace(r.ports, ":", ",")) : tonumber(p) >= 1 && tonumber(p) <= 65535]), false)])
    error_message = "Dependency exceptions must target a single IPv4 /32, TCP/UDP, and explicit destination ports."
  }
}

# Pass the SAME -var-file=../he-ipv6.tfvars to home and host-config.
# Missing teardown credentials fail against a reserved invalid hostname;
# unused default-off configurations never connect or fall back to localhost.
provider "system" {
  alias = "ingress"
  ssh {
    host     = var.proxmox_ssh == null ? "disabled.invalid" : var.proxmox_ssh.host
    user     = var.proxmox_ssh == null ? "root" : var.proxmox_ssh.user
    port     = var.proxmox_ssh == null ? 22 : var.proxmox_ssh.port
    host_key = var.proxmox_ssh == null ? null : var.proxmox_ssh.host_key
    agent    = true
  }
  sudo = var.proxmox_ssh == null ? false : var.proxmox_ssh.user != "root"
}
variable "he_ipv6" {
  description = "Optional HE tunnel and shared public IPv6. Disabled unless explicitly enabled in both roots."
  type = object({
    enabled         = optional(bool, false)
    server_ipv4     = optional(string)
    local_ipv4      = optional(string)
    client_ipv6     = optional(string)
    server_ipv6     = optional(string)
    routed_prefix   = optional(string)
    ula_prefix      = optional(string)
    mtu             = optional(number, 1480)
    protected_cidrs = optional(list(string), [])
    port_forwards   = optional(map(object({ guest = string, port = number })), {})
  })
  default  = {}
  nullable = false
  validation {
    condition = !var.he_ipv6.enabled || try(
      can(cidrnetmask("${var.he_ipv6.server_ipv4}/32")) &&
      cidrhost("${var.he_ipv6.server_ipv4}/32", 0) == var.he_ipv6.server_ipv4 &&
      can(cidrnetmask("${var.he_ipv6.local_ipv4}/32")) &&
      strcontains(var.he_ipv6.client_ipv6, ":") && split("/", var.he_ipv6.client_ipv6)[1] == "64" &&
      cidrhost("${split("/", var.he_ipv6.client_ipv6)[0]}/3", 0) == "2000::" &&
      strcontains(var.he_ipv6.server_ipv6, ":") &&
      cidrhost("${var.he_ipv6.server_ipv6}/64", 0) == cidrhost(var.he_ipv6.client_ipv6, 0) &&
      cidrhost("${var.he_ipv6.server_ipv6}/128", 0) != cidrhost("${split("/", var.he_ipv6.client_ipv6)[0]}/128", 0) &&
      split("/", var.he_ipv6.routed_prefix)[1] == "64" &&
      cidrhost(var.he_ipv6.routed_prefix, 0) == split("/", var.he_ipv6.routed_prefix)[0] &&
      cidrhost("${split("/", var.he_ipv6.routed_prefix)[0]}/3", 0) == "2000::" &&
      cidrhost(var.he_ipv6.routed_prefix, 0) != cidrhost(var.he_ipv6.client_ipv6, 0) &&
      split("/", var.he_ipv6.ula_prefix)[1] == "48" &&
      cidrhost(var.he_ipv6.ula_prefix, 0) == split("/", var.he_ipv6.ula_prefix)[0] &&
      cidrhost("${split("/", var.he_ipv6.ula_prefix)[0]}/8", 0) == "fd00::" &&
      var.he_ipv6.mtu >= 1280 && var.he_ipv6.mtu <= 1480 && floor(var.he_ipv6.mtu) == var.he_ipv6.mtu &&
      alltrue([for c in var.he_ipv6.protected_cidrs : strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0]]) &&
      length(distinct([for f in values(var.he_ipv6.port_forwards) : f.port])) == length(var.he_ipv6.port_forwards) &&
      alltrue([for f in values(var.he_ipv6.port_forwards) :
        can(regex("^[a-z][a-z0-9-]{0,62}$", f.guest)) && f.port >= 1 && f.port <= 65535 && floor(f.port) == f.port && !contains([22, 8006], f.port)
    ]), false)
    error_message = "Enabled HE requires valid IPv4 endpoints, distinct global tunnel IPv6 endpoints in one /64, a separate canonical global routed /64, canonical fd00::/8 ULA /48, integer MTU 1280..1480, IPv6 protected CIDRs and unique valid non-management TCP ports."
  }
  validation {
    condition = !var.he_ipv6.enabled || try(
      var.he_ipv6.local_ipv4 == var.host_address && var.proxmox_ssh != null &&
      alltrue([for f in values(var.he_ipv6.port_forwards) :
        contains([for p in var.guests[f.guest].public_ports : p.port if p.protocol == "tcp"], f.port)
      ]) &&
      alltrue([for name, g in var.guests : g.slot <= 65535 if
        contains([for f in values(var.he_ipv6.port_forwards) : f.guest], name) || length(local.effective_internet_egress_ports[name]) > 0
    ]), false)
    error_message = "Enabled HE needs host_address as local IPv4, Proxmox SSH, declared TCP public_ports on every forwarding target, and slots <=65535 for all IPv6 participants."
  }
}
locals {
  he_ipv6_public_address = var.he_ipv6.enabled ? try(cidrhost(var.he_ipv6.routed_prefix, 2), null) : null
}

locals {
  he_ipv6_participants = var.he_ipv6.enabled ? toset([for name, g in var.guests : name if
    contains([for f in values(var.he_ipv6.port_forwards) : f.guest], name) || length(local.effective_internet_egress_ports[name]) > 0
  ]) : toset([])
  effective_internet_egress_ports = { for name, g in var.guests : name => distinct(concat(
    var.internet_egress_ports, g.internet_egress_ports,
    g.role == "monitoring" ? [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] : []
  )) }
}
locals {
  he_ipv6_firewall_bridges = tomap({ for name in local.he_ipv6_participants : "fwbr${var.guests[name].vm_id}i0" => local.he_ipv6_networks[name].address })
  he_ipv6_networks = { for name in local.he_ipv6_participants : name => merge(
    module.network.networks[name].ipv6, { vnet_id = module.network.networks[name].vnet_id }
  ) }
  he_ipv6_forwards = var.he_ipv6.enabled ? { for key, f in var.he_ipv6.port_forwards : key => {
    guest   = f.guest, port = f.port, address = module.network.networks[f.guest].ipv6.address,
    vnet_id = var.guests[f.guest].vnet_id
  } } : {}
  he_ipv6_egress = { for name in local.he_ipv6_participants : name => {
    address = local.he_ipv6_networks[name].address, vnet_id = var.guests[name].vnet_id,
    ports   = local.effective_internet_egress_ports[name]
  } if length(local.effective_internet_egress_ports[name]) > 0 }
  he_ipv6_protected = var.he_ipv6.enabled ? concat(
    [var.he_ipv6.ula_prefix, var.he_ipv6.routed_prefix, "${cidrhost(var.he_ipv6.client_ipv6, 0)}/64"], var.he_ipv6.protected_cidrs
  ) : []
  he_host_allow_rules = !var.he_ipv6.enabled ? [] : concat(
    [merge(local.host_rule, {
      source = "${var.he_ipv6.server_ipv4}/32", dest = "${var.host_address}/32", proto = "41", comment = "hsp:host:he-transport"
    })],
    [for kind in [1, 2, 3, 4] : merge(local.host_rule, {
      source = "::/0", proto = "icmpv6", dport = tostring(kind), iface = "hsp-he6", comment = "hsp:host:he-error:${kind}"
    })],
    flatten([for name in local.he_ipv6_participants : [for kind in [135, 136] : merge(local.host_rule, {
      source = join(",", concat(["${local.he_ipv6_networks[name].address}/128", "fe80::/10"], kind == 135 ? ["::/128"] : [])),
      dest   = join(",", ["${local.he_ipv6_networks[name].gateway}/128", "fe80::/10", "ff02::1:ff00:0/104", "ff02::1/128"]),
      proto  = "icmpv6", dport = tostring(kind), iface = var.guests[name].vnet_id, comment = "hsp:host:he-ndp:${name}:${kind}"
    })]])
  )
}
module "ipv6_ingress" {
  count            = var.he_ipv6.enabled && (length(local.he_ipv6_forwards) > 0 || length(local.he_ipv6_egress) > 0) ? 1 : 0
  source           = "../../modules/ipv6_ingress"
  providers        = { system = system.ingress }
  proxmox_ssh      = var.proxmox_ssh
  public_address   = local.he_ipv6_public_address
  ula_prefix       = var.he_ipv6.ula_prefix
  protected_cidrs  = local.he_ipv6_protected
  forwards         = local.he_ipv6_forwards
  egress           = local.he_ipv6_egress
  firewall_bridges = local.he_ipv6_firewall_bridges
  depends_on       = [module.network, module.service]
}

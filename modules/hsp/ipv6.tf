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
    alltrue([for c in var.he_ipv6.protected_cidrs : strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0]]), false)
    error_message = "Enabled HE requires valid IPv4 endpoints, distinct global tunnel IPv6 endpoints in one /64, a separate canonical global routed /64, canonical fd00::/8 ULA /48, integer MTU 1280..1480, IPv6 protected CIDRs."
  }
  validation {
    condition = !var.he_ipv6.enabled || try(
      var.he_ipv6.local_ipv4 == var.host_address && var.proxmox_ssh != null &&
    alltrue([for name in local.he_ipv6_eligible_participants : var.guests[name].slot <= 65535]), false)
    error_message = "Enabled HE needs host_address as local IPv4, Proxmox SSH and slots <=65535 for all IPv6 participants."
  }
  validation {
    condition     = !var.he_ipv6.enabled || alltrue([for owners in values(local.he_ipv6_forward_owners) : length(owners) == 1])
    error_message = "Conflicting public_ports: each TCP/UDP protocol-port pair must belong to exactly one guest. Conflicts: ${join(", ", [for key, owners in local.he_ipv6_forward_owners : "${key} (${join(", ", sort(tolist(owners)))})" if length(owners) > 1])}."

  }
}
locals {
  he_ipv6_public_address = var.he_ipv6.enabled ? try(cidrhost(var.he_ipv6.routed_prefix, 2), null) : null
}

locals {
  # Group before resolving so conflicts produce a blocking diagnostic rather
  # than a duplicate-key error or an arbitrary forwarding destination.
  he_ipv6_public_ports = distinct(flatten([for name, g in var.guests : [for p in g.public_ports : {
    guest = name, protocol = p.protocol, port = p.port
  }]]))
  he_ipv6_forward_groups = { for f in local.he_ipv6_public_ports : "${f.protocol}-${f.port}" => f... }
  he_ipv6_forward_owners = { for key, forwards in local.he_ipv6_forward_groups : key => toset([for f in forwards : f.guest]) }
  # Authorize before resolving addresses so participation and native/router
  # rules all follow the same permission decision without a network cycle.
  he_ipv6_hairpin_permissions = { for source in keys(var.guests) : source => toset([
    for key, forwards in local.he_ipv6_forward_groups : key
    if length(local.he_ipv6_forward_owners[key]) == 1 && (
      anytrue([for p in local.effective_internet_egress_ports[source] :
        p.protocol == forwards[0].protocol && p.port == forwards[0].port
        ]) || anytrue([for c in var.connections :
        c.from == source && c.to == forwards[0].guest && c.protocol == forwards[0].protocol && c.port == forwards[0].port
      ])
    )
  ]) }
  he_ipv6_eligible_participants = toset([for name, g in var.guests : name if
    length(g.public_ports) > 0 || length(local.effective_internet_egress_ports[name]) > 0 || length(local.he_ipv6_hairpin_permissions[name]) > 0
  ])
  he_ipv6_participants = var.he_ipv6.enabled ? local.he_ipv6_eligible_participants : toset([])
  effective_internet_egress_ports = { for name, g in var.guests : name => distinct(concat(
    var.internet_egress_ports, g.internet_egress_ports,
    g.role == "monitoring" ? [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] : []
  )) }
}
locals {
  # Reaching a public VIP must respect the source's existing permissions.
  # Explicit guest connections match the resolved owner, direction and service;
  # role-generated IPv4 connections do not implicitly authorize IPv6 hairpin.
  he_ipv6_hairpin = { for h in flatten([
    for source in local.he_ipv6_participants : [for key, f in local.he_ipv6_forwards : {
      source_guest   = source
      source_address = local.he_ipv6_networks[source].address
      source_vnet_id = var.guests[source].vnet_id
      forward_key    = key
      target_guest   = f.guest
      target_address = f.address
      target_vnet_id = f.vnet_id
      target_gateway = local.he_ipv6_networks[f.guest].gateway
      protocol       = f.protocol
      port           = f.port
    } if contains(local.he_ipv6_hairpin_permissions[source], key)]
  ]) : "${h.source_guest}/${h.forward_key}" => h }
  he_ipv6_firewall_bridges = tomap({ for name in local.he_ipv6_participants : "fwbr${var.guests[name].vm_id}i0" => local.he_ipv6_networks[name].address })
  he_ipv6_networks = { for name in local.he_ipv6_participants : name => merge(
    module.network.networks[name].ipv6, { vnet_id = module.network.networks[name].vnet_id }
  ) }
  he_ipv6_forwards = var.he_ipv6.enabled ? { for key, forwards in local.he_ipv6_forward_groups : key => {
    guest   = forwards[0].guest, protocol = forwards[0].protocol, port = forwards[0].port,
    address = module.network.networks[forwards[0].guest].ipv6.address,
    vnet_id = var.guests[forwards[0].guest].vnet_id
  } if length(local.he_ipv6_forward_owners[key]) == 1 } : {}
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
  count            = var.he_ipv6.enabled && (length(local.he_ipv6_forwards) > 0 || length(local.he_ipv6_egress) > 0 || length(local.he_ipv6_hairpin) > 0) ? 1 : 0
  source           = "../ipv6_ingress"
  providers        = { system = system.ingress }
  proxmox_ssh      = var.proxmox_ssh
  public_address   = local.he_ipv6_public_address
  ula_prefix       = var.he_ipv6.ula_prefix
  protected_cidrs  = local.he_ipv6_protected
  forwards         = local.he_ipv6_forwards
  egress           = local.he_ipv6_egress
  hairpin          = local.he_ipv6_hairpin
  firewall_bridges = local.he_ipv6_firewall_bridges
  depends_on       = [module.network, module.service]
}

locals {
  administrators = [for name, g in var.guests : name if g.role == "admin_vpn"]
  role_connections = concat(
    flatten([for admin in local.administrators : [for name in keys(var.guests) : {
      from = admin, to = name, protocol = "tcp", port = 22
    } if name != admin]]),
    [for name, g in var.guests : {
      from = name, to = var.private_proxy_name, protocol = "tcp", port = 443
    } if g.role == "service_vpn" && var.private_proxy_name != null],
    [for name in keys(var.guests) : {
      from = name, to = var.http_proxy_name, protocol = "tcp", port = 3128
    } if name != var.http_proxy_name && contains(keys(var.guests), coalesce(var.http_proxy_name, "-"))]
  )
  connections = distinct(concat(var.connections, local.role_connections))
  monitoring_connections = flatten([for monitor, g in var.guests : [for name in keys(var.guests) : [for protocol in ["tcp", "udp"] : {
    from = monitor, to = name, protocol = protocol
  }] if name != monitor] if g.role == "monitoring"])
  allow_rules = { for name, g in var.guests : name => concat(
    [for cidr in var.bootstrap_admin_cidrs : {
      direction = "in", address = cidr, protocol = "tcp", ports = "22", description = "bootstrap SSH:${cidr}"
    } if g.bootstrap],
    [for c in local.connections : {
      direction = "out", address = "${try(module.network.networks[c.to].address, c.to)}/32", protocol = c.protocol,
      ports     = tostring(c.port), description = "${c.from}->${c.to}:${c.port}"
    } if c.from == name],
    [for c in local.connections : {
      direction = "in", address = "${trimsuffix(try(module.network.networks[c.from].address, c.from), "/32")}/32", protocol = c.protocol,
      ports     = tostring(c.port), description = "${c.from}->${c.to}:${c.port}"
    } if c.to == name],
    [for c in local.monitoring_connections : {
      direction = "out", address = "${module.network.networks[c.to].address}/32", protocol = c.protocol,
      ports     = "1:65535", description = "monitoring:${c.from}->${c.to}:${c.protocol}"
    } if c.from == name],
    [for c in local.monitoring_connections : {
      direction = "in", address = "${module.network.networks[c.from].address}/32", protocol = c.protocol,
      ports     = "1:65535", description = "monitoring:${c.from}->${c.to}:${c.protocol}"
    } if c.to == name],
    g.role == "admin_vpn" ? [{
      direction = "out", address = "${var.host_address}/32", protocol = "tcp", ports = "22,8006", description = "host management"
    }] : []
  ) }
  dns_entries = flatten([for name, g in var.guests : [for alias, d in g.dns : {
    name          = alias, mode = d.mode, guest = name,
    proxy_address = d.mode == "proxy" ? (d.proxy_name != null ? try(module.network.networks[d.proxy_name].address, null) : d.proxy_address) : null
  }]])
  host_rule = { type = "in", action = "ACCEPT", source = null, dest = null, proto = null, dport = null, iface = null, comment = "", enabled = true }
  host_rules = concat(
    local.he_host_allow_rules,
    [for c in var.bootstrap_admin_cidrs : merge(local.host_rule, { source = c, proto = "tcp", dport = "22,8006", comment = "hsp:host:bootstrap:${c}" })],
    [for name in local.administrators : merge(local.host_rule, { source = "${module.network.networks[name].address}/32", proto = "tcp", dport = "22,8006", comment = "hsp:host:admin:${name}" })],
    [for n in values(var.guests) : merge(local.host_rule, { source = "::/0", iface = n.vnet_id, action = "DROP", comment = "hsp:host:deny-ipv6:${n.vnet_id}" })],
    [merge(local.host_rule, { source = var.platform_cidr, action = "DROP", comment = "hsp:host:deny-platform" })],
    [for c in var.protected_cidrs : merge(local.host_rule, { source = c, action = "DROP", comment = "hsp:host:deny-protected:${c}" })],
    [merge(local.host_rule, { source = "0.0.0.0/0", action = "DROP", comment = "hsp:host:deny-other-ipv4" }),
    merge(local.host_rule, { source = "::/0", action = "DROP", comment = "hsp:host:deny-other-ipv6" })]
  )
}

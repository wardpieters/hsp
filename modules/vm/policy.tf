locals {
  base_rule = { type = "in", action = "ACCEPT", source = null, dest = null, proto = null, dport = null, comment = "" }
  protected = distinct(concat(var.protected_cidrs, [
    "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
    "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4"
  ]))
  rules = concat(
    [merge(local.base_rule, { action = "DROP", source = "::/0", comment = "hsp:ipv6-in" }),
    merge(local.base_rule, { type = "out", action = "DROP", dest = "::/0", comment = "hsp:ipv6-out" })],
    [for r in var.allow_rules : merge(local.base_rule, {
      type    = r.direction, source = r.direction == "in" ? r.address : null,
      dest    = r.direction == "out" ? r.address : null, proto = r.protocol, dport = r.ports,
      comment = "hsp:allow:${r.description}"
    })],
    flatten([for ip in var.dns_servers : [for proto in ["tcp", "udp"] : merge(local.base_rule, {
      type = "out", dest = "${ip}/32", proto = proto, dport = "53", comment = "hsp:dns:${proto}:${ip}"
    })]]),
    [for ip in var.ntp_servers : merge(local.base_rule, {
      type = "out", dest = "${ip}/32", proto = "udp", dport = "123", comment = "hsp:ntp:${ip}"
    })],
    flatten([for c in local.protected : [
      merge(local.base_rule, { action = "DROP", source = c, comment = "hsp:protect-in:${c}" }),
      merge(local.base_rule, { type = "out", action = "DROP", dest = c, comment = "hsp:protect-out:${c}" })
    ]]),
    [for p in var.public_ports : merge(local.base_rule, {
      source = "0.0.0.0/0", proto = p.protocol, dport = tostring(p.port), comment = "hsp:public:${p.protocol}:${p.port}"
    })],
    var.allow_updates ? [merge(local.base_rule, {
      type = "out", dest = "0.0.0.0/0", proto = "tcp", dport = "80,443", comment = "hsp:updates"
    })] : []
  )
}

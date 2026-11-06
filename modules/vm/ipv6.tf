variable "ipv6_forwarded_ports" {
  type    = list(number)
  default = []
  validation {
    condition     = alltrue([for port in var.ipv6_forwarded_ports : contains([for p in var.public_ports : p.port if p.protocol == "tcp"], port)])
    error_message = "IPv6 forwarded ports must already be declared TCP public_ports."
  }
}
variable "protected_ipv6_cidrs" {
  type    = list(string)
  default = []
  validation {
    condition     = alltrue([for c in var.protected_ipv6_cidrs : try(strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "Protected IPv6 ranges must be canonical IPv6 CIDRs."
  }
}
locals {
  ipv6_protected = distinct(concat(var.protected_ipv6_cidrs, ["::/128", "::1/128", "::ffff:0:0/96", "100::/64", "fc00::/7", "fe80::/10", "ff00::/8"]))
  # No implicit NDP option: it would also permit unwanted router traffic.
  ipv6_rules = var.network.ipv6 == null ? [
    merge(local.base_rule, { action = "DROP", source = "::/0", comment = "hsp:ipv6-in" }),
    merge(local.base_rule, { type = "out", action = "DROP", dest = "::/0", comment = "hsp:ipv6-out" })
    ] : concat(
    flatten([for direction in ["in", "out"] : [for kind in [135, 136] : merge(local.base_rule, {
      type    = direction, proto = "icmpv6", dport = tostring(kind),
      source  = join(",", concat(["${direction == "in" ? var.network.ipv6.gateway : var.network.ipv6.address}/128", "fe80::/10"], kind == 135 ? ["::/128"] : [])),
      dest    = join(",", ["${direction == "in" ? var.network.ipv6.address : var.network.ipv6.gateway}/128", "fe80::/10", "ff02::1:ff00:0/104", "ff02::1/128"]),
      comment = "hsp:ipv6:ndp:${direction}:${kind}"
    })]]),
    flatten([for direction in ["in", "out"] : [for kind in [1, 2, 3, 4] : merge(local.base_rule, {
      type    = direction, proto = "icmpv6", dport = tostring(kind),
      source  = direction == "out" ? "${var.network.ipv6.address}/128" : "::/0",
      dest    = direction == "in" ? "${var.network.ipv6.address}/128" : null,
      comment = "hsp:ipv6:error:${direction}:${kind}"
    })]]),
    [for direction in ["in", "out"] : merge(local.base_rule, {
      type = direction, action = "DROP", source = "::/128", comment = "hsp:ipv6:unspecified:${direction}"
    })],
    flatten([for direction in ["in", "out"] : [for kind in [130, 131, 132, 133, 134, 135, 136, 137, 143] : merge(local.base_rule, {
      type    = direction, action = "DROP", proto = "icmpv6", dport = tostring(kind),
      source  = direction == "in" ? "::/0" : null, dest = direction == "out" ? "::/0" : null,
      comment = "hsp:ipv6:deny-control:${direction}:${kind}"
    })]]),
    flatten([for c in local.ipv6_protected : [
      merge(local.base_rule, { action = "DROP", source = c, comment = "hsp:ipv6:protect-in:${c}" }),
      merge(local.base_rule, { type = "out", action = "DROP", dest = c, comment = "hsp:ipv6:protect-out:${c}" })
    ]]),
    [for port in distinct(var.ipv6_forwarded_ports) : merge(local.base_rule, {
      source = "::/0", proto = "tcp", dport = tostring(port), comment = "hsp:ipv6:public:tcp:${port}"
    })],
    [for p in var.internet_egress_ports : merge(local.base_rule, {
      type    = "out", dest = "::/0", proto = p.protocol == "icmp" ? "ipv6-icmp" : p.protocol,
      dport   = p.protocol == "icmp" ? null : tostring(p.port),
      comment = p.protocol == "icmp" ? "hsp:ipv6:internet:icmp" : "hsp:ipv6:internet:${p.protocol}:${p.port}"
    })]
  )
}

output "guests" {
  value = { for name, g in module.service : name => {
    vm_id = g.vm_id, type = g.type, address = g.address, names = g.names, started = var.guests[name].started
  } }
}
output "router_route" {
  value = { destination = var.platform_cidr, next_hop = var.host_address }
}
output "public_forwards" {
  value = flatten([for name, g in var.guests : [for p in g.public_ports : {
    guest = name, address = module.network.networks[name].address, protocol = p.protocol, port = p.port
  }]])
}
output "host_policy" {
  value     = local.host_rules
  sensitive = true
}
output "policies" {
  value     = { for name, service in module.service : name => service.rules }
  sensitive = true
}
output "dns_targets" {
  value = { for d in local.dns_entries : d.name => d.mode == "proxy" ? d.proxy_address : module.network.networks[d.guest].address if d.mode != "none" }
}
output "ipv6_ingress" {
  value = var.he_ipv6.enabled ? { public_address = local.he_ipv6_public_address, routed_prefix = var.he_ipv6.routed_prefix, ula_prefix = var.he_ipv6.ula_prefix } : null
}
output "ipv6_networks" { value = local.he_ipv6_networks }
output "ipv6_port_forwards" {
  value = { for key, f in local.he_ipv6_forwards : key => {
    public_address = local.he_ipv6_public_address, protocol = f.protocol, port = f.port,
    guest          = f.guest, target_address = f.address, vnet_id = f.vnet_id
  } }
}
output "ipv6_egress" {
  value = { for name, e in local.he_ipv6_egress : name => {
    public_address = local.he_ipv6_public_address, source_address = e.address, vnet_id = e.vnet_id, ports = e.ports
  } }
}
output "ipv6_host_requirements" {
  value = [for r in local.he_host_allow_rules : {
    purpose  = r.comment, direction = r.type, iface = r.iface, source = r.source, destination = r.dest,
    protocol = r.proto, icmp_type = r.proto == "icmpv6" ? r.dport : null
  }]
}

output "ipv6_hairpin" {
  value = { for key, h in local.he_ipv6_hairpin : key => {
    source_guest              = h.source_guest, source_address = h.source_address, source_vnet_id = h.source_vnet_id,
    forward_key               = h.forward_key, public_address = local.he_ipv6_public_address, protocol = h.protocol, port = h.port,
    target_guest              = h.target_guest, target_address = h.target_address, target_vnet_id = h.target_vnet_id,
    translated_source_address = h.target_gateway
  } }
}

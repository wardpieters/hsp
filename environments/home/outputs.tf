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

output "guests" {
  value = { for name, g in module.service : name => {
    vm_id = g.vm_id, address = g.address, names = g.names, started = var.guests[name].started
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
output "activation_context" {
  value = { endpoint = var.proxmox_endpoint, platform_cidr = var.platform_cidr, host_rules = local.host_rules }
}
output "policies" { value = { for name, service in module.service : name => service.rules } }
output "dns_targets" {
  value = { for d in local.dns_entries : d.name => d.mode == "proxy" ? d.proxy_address : module.network.networks[d.guest].address if d.mode != "none" }
}

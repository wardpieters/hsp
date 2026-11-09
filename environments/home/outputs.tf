output "guests" {
  value = module.hsp.guests
}

output "router_route" {
  value = module.hsp.router_route
}

output "public_forwards" {
  value = module.hsp.public_forwards
}

output "host_policy" {
  value     = module.hsp.host_policy
  sensitive = true
}

output "policies" {
  value     = module.hsp.policies
  sensitive = true
}

output "dns_targets" {
  value = module.hsp.dns_targets
}

output "ipv6_ingress" {
  value = module.hsp.ipv6_ingress
}

output "ipv6_networks" {
  value = module.hsp.ipv6_networks
}

output "ipv6_port_forwards" {
  value = module.hsp.ipv6_port_forwards
}

output "ipv6_egress" {
  value = module.hsp.ipv6_egress
}

output "ipv6_host_requirements" {
  value = module.hsp.ipv6_host_requirements
}

output "ipv6_hairpin" {
  value = module.hsp.ipv6_hairpin
}

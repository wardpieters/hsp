# Preserve addresses when adopting the reusable platform module.

moved {
  from = module.network
  to   = module.hsp.module.network
}

moved {
  from = module.service
  to   = module.hsp.module.service
}

moved {
  from = module.ipv6_ingress
  to   = module.hsp.module.ipv6_ingress
}

moved {
  from = proxmox_virtual_environment_cluster_firewall.this
  to   = module.hsp.proxmox_virtual_environment_cluster_firewall.this
}

moved {
  from = proxmox_node_firewall.this
  to   = module.hsp.proxmox_node_firewall.this
}

moved {
  from = proxmox_virtual_environment_firewall_rules.host
  to   = module.hsp.proxmox_virtual_environment_firewall_rules.host
}

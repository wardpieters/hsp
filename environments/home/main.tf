# Reusable platform composition. Provider configuration stays in this root.
module "hsp" {
  source = "../../modules/hsp"
  providers = {
    proxmox        = proxmox
    pihole         = pihole
    restful        = restful
    system.ingress = system.ingress
  }
  node_name              = var.node_name
  proxmox_ssh            = var.proxmox_ssh
  platform_cidr          = var.platform_cidr
  host_address           = var.host_address
  protected_cidrs        = var.protected_cidrs
  bootstrap_admin_cidrs  = var.bootstrap_admin_cidrs
  public_ports_lan_cidrs = var.public_ports_lan_cidrs
  service_access_cidrs   = var.service_access_cidrs
  manage_host_firewall   = var.manage_host_firewall
  dns_servers            = var.dns_servers
  domain                 = var.domain
  ntp_servers            = var.ntp_servers
  internet_egress_ports  = var.internet_egress_ports
  vm_template_id         = var.vm_template_id
  lxc_template           = var.lxc_template
  datastore_id           = var.datastore_id
  ssh_public_keys        = var.ssh_public_keys
  http_proxy_name        = var.http_proxy_name
  private_proxy_name     = var.private_proxy_name
  guests                 = var.guests
  connections            = var.connections
  he_ipv6                = var.he_ipv6
}

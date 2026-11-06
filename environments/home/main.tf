provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = var.proxmox_insecure_tls
  api_token = var.proxmox_api_token
}
provider "restful" {
  base_url = "${trimsuffix(var.proxmox_endpoint, "/")}/api2/json"
  client   = { tls_insecure_skip_verify = var.proxmox_insecure_tls }
  security = {
    apikey = [{ in = "header", name = "Authorization", value = "PVEAPIToken=${var.proxmox_api_token}" }]
  }
}
provider "pihole" {
  url          = var.pihole_url
  password     = var.pihole_password
  insecure_tls = var.pihole_insecure_tls
}
module "network" {
  source          = "../../modules/platform_network"
  node_name       = var.node_name
  platform_cidr   = var.platform_cidr
  protected_cidrs = var.protected_cidrs
  networks = { for name, g in var.guests : name => {
    slot      = g.slot, vnet_id = g.vnet_id,
    ipv6_cidr = contains(local.he_ipv6_participants, name) ? try(cidrsubnet(var.he_ipv6.ula_prefix, 16, g.slot), null) : null
  } }
}
module "service" {
  for_each               = var.guests
  source                 = "../../modules/service_vm"
  node_name              = var.node_name
  network                = module.network.networks[each.key]
  ipv6_forwarded_ports   = var.he_ipv6.enabled ? [for f in values(var.he_ipv6.port_forwards) : f.port if f.guest == each.key] : []
  ipv6_hairpin_out       = distinct([for h in values(local.he_ipv6_hairpin) : { public_address = local.he_ipv6_public_address, port = h.port } if h.source_guest == each.key])
  ipv6_hairpin_in        = distinct([for h in values(local.he_ipv6_hairpin) : { gateway = h.target_gateway, port = h.port } if h.target_guest == each.key])
  protected_ipv6_cidrs   = local.he_ipv6_protected
  protected_cidrs        = concat([var.platform_cidr, "${var.host_address}/32"], var.protected_cidrs)
  dns_servers            = var.dns_servers
  domain                 = var.domain
  ntp_servers            = var.ntp_servers
  ssh_public_keys        = var.ssh_public_keys
  public_ports_lan_cidrs = var.public_ports_lan_cidrs
  service_access_cidrs   = each.key == var.private_proxy_name ? var.service_access_cidrs : []
  lxc_template           = var.lxc_template
  proxmox_ssh            = var.proxmox_ssh
  guest = {
    name                  = each.key, vm_id = each.value.vm_id, vm_template_id = var.vm_template_id, datastore_id = var.datastore_id,
    type                  = each.value.type, nesting = each.value.nesting, mount_points = each.value.mount_points,
    lxc_mounts            = each.value.lxc_mounts, lxc_cgroups = each.value.lxc_cgroups,
    started               = each.value.started, on_boot = each.value.on_boot, cores = each.value.cores,
    memory_mb             = each.value.memory_mb, disk_gb = each.value.disk_gb,
    backup                = each.value.backup,
    ssd                   = each.value.ssd,
    extra_disks           = each.value.extra_disks,
    internet_egress_ports = local.effective_internet_egress_ports[each.key],
    public_ports          = each.value.public_ports, allow_rules = local.allow_rules[each.key],
    dns                   = { for d in local.dns_entries : d.name => { mode = d.mode, proxy_address = d.proxy_address } if d.guest == each.key }
  }
}

# Full-ruleset ownership is an explicit deployment choice after inventory/import.
resource "proxmox_virtual_environment_cluster_firewall" "this" {
  count         = var.manage_host_firewall ? 1 : 0
  enabled       = true
  ebtables      = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  depends_on    = [proxmox_virtual_environment_firewall_rules.host]
}
resource "proxmox_node_firewall" "this" {
  count      = var.manage_host_firewall ? 1 : 0
  node_name  = var.node_name
  enabled    = true
  nftables   = false
  depends_on = [proxmox_virtual_environment_firewall_rules.host]
}
resource "proxmox_virtual_environment_firewall_rules" "host" {
  count     = var.manage_host_firewall ? 1 : 0
  node_name = var.node_name
  dynamic "rule" {
    for_each = local.host_rules
    content {
      type    = rule.value.type
      action  = rule.value.action
      source  = rule.value.source
      dest    = rule.value.dest
      proto   = rule.value.proto
      dport   = rule.value.dport
      iface   = rule.value.iface
      comment = rule.value.comment
      enabled = true
    }
  }
}

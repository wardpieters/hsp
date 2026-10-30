variable "guest" {
  type = object({
    name                  = string, vm_id = number, vm_template_id = optional(number), datastore_id = string,
    type                  = optional(string, "vm"),
    started               = optional(bool, false), on_boot = optional(bool, false), cores = optional(number, 2),
    memory_mb             = optional(number, 2048), disk_gb = optional(number, 16),
    backup                = optional(bool, true),
    mount_points          = optional(list(object({ path = string, size_gb = number, datastore_id = optional(string), backup = optional(bool, true) })), []),
    internet_egress_ports = optional(list(object({ protocol = string, port = number })), []),
    public_ports          = optional(list(object({ protocol = string, port = number })), []),
    allow_rules           = optional(list(object({ direction = string, address = string, protocol = string, ports = string, description = string })), []),
    dns                   = optional(map(object({ mode = string, proxy_address = optional(string) })), {})
  })
}
variable "node_name" { type = string }
variable "network" { type = object({ address = string, gateway = string, cidr = string, vnet_id = string }) }
variable "protected_cidrs" { type = list(string) }
variable "dns_servers" { type = list(string) }
variable "ntp_servers" { type = list(string) }
variable "ssh_public_keys" { type = list(string) }
variable "public_ports_lan_cidrs" {
  type     = list(string)
  default  = []
  nullable = false
}
variable "service_access_cidrs" {
  type     = list(string)
  default  = []
  nullable = false
}
variable "lxc_template" {
  type    = object({ file_id = string, os_type = optional(string, "debian") })
  default = null
}

module "vm" {
  source                 = "../vm"
  name                   = var.guest.name
  node_name              = var.node_name
  vm_id                  = var.guest.vm_id
  guest_type             = var.guest.type
  lxc_template           = var.lxc_template
  mount_points           = var.guest.mount_points
  vm_template_id         = var.guest.vm_template_id
  datastore_id           = var.guest.datastore_id
  network                = var.network
  started                = var.guest.started
  on_boot                = var.guest.on_boot
  cores                  = var.guest.cores
  memory_mb              = var.guest.memory_mb
  disk_gb                = var.guest.disk_gb
  backup                 = var.guest.backup
  protected_cidrs        = var.protected_cidrs
  dns_servers            = var.dns_servers
  ntp_servers            = var.ntp_servers
  ssh_public_keys        = var.ssh_public_keys
  internet_egress_ports  = var.guest.internet_egress_ports
  public_ports           = var.guest.public_ports
  public_ports_lan_cidrs = var.public_ports_lan_cidrs
  service_access_cidrs   = var.service_access_cidrs
  allow_rules            = var.guest.allow_rules
}
module "dns" {
  source  = "../dns_records"
  records = { for name, r in var.guest.dns : name => { mode = r.mode, address = var.network.address, proxy_address = r.proxy_address } }
}
output "address" { value = var.network.address }
output "vm_id" { value = module.vm.vm_id }
output "type" { value = module.vm.guest_type }
output "names" { value = module.dns.names }
output "rules" { value = module.vm.rules }

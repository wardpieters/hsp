variable "guest" {
  type = object({
    name         = string, vm_id = number, template_id = number, datastore_id = string,
    started      = optional(bool, false), on_boot = optional(bool, false), cores = optional(number, 2),
    memory_mb    = optional(number, 2048), disk_gb = optional(number, 16), allow_updates = optional(bool, false),
    backup       = optional(bool, true),
    public_ports = optional(list(object({ protocol = string, port = number })), []),
    allow_rules  = optional(list(object({ direction = string, address = string, protocol = string, ports = string, description = string })), []),
    dns          = optional(map(object({ mode = string, proxy_address = optional(string) })), {})
  })
}
variable "node_name" { type = string }
variable "network" { type = object({ address = string, gateway = string, cidr = string, vnet_id = string }) }
variable "protected_cidrs" { type = list(string) }
variable "dns_servers" { type = list(string) }
variable "ntp_servers" { type = list(string) }
variable "ssh_public_keys" { type = list(string) }

module "vm" {
  source          = "../vm"
  name            = var.guest.name
  node_name       = var.node_name
  vm_id           = var.guest.vm_id
  template_id     = var.guest.template_id
  datastore_id    = var.guest.datastore_id
  network         = var.network
  started         = var.guest.started
  on_boot         = var.guest.on_boot
  cores           = var.guest.cores
  memory_mb       = var.guest.memory_mb
  disk_gb         = var.guest.disk_gb
  backup          = var.guest.backup
  protected_cidrs = var.protected_cidrs
  dns_servers     = var.dns_servers
  ntp_servers     = var.ntp_servers
  ssh_public_keys = var.ssh_public_keys
  allow_updates   = var.guest.allow_updates
  public_ports    = var.guest.public_ports
  allow_rules     = var.guest.allow_rules
}
module "dns" {
  source  = "../dns_records"
  records = { for name, r in var.guest.dns : name => { mode = r.mode, address = var.network.address, proxy_address = r.proxy_address } }
}
output "address" { value = var.network.address }
output "vm_id" { value = module.vm.vm_id }
output "names" { value = module.dns.names }
output "rules" { value = module.vm.rules }

variable "platform_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.platform_cidr))
    error_message = "Supply the canonical private aggregate; the host helper verifies RFC1918 membership."
  }
}
resource "system_folder" "startup_dropin" {
  path = "/etc/systemd/system/pve-guests.service.d"
  mode = "755"
  uid  = 0
  gid  = 0
}
resource "system_file" "startup_guard" {
  path    = "${system_folder.startup_dropin.path}/hsp.conf"
  content = "[Unit]\nRequires=hsp-proxmox.service pve-firewall.service\nAfter=hsp-proxmox.service pve-firewall.service\n"
  mode    = "644"
  uid     = 0
  gid     = 0
}
module "service" {
  source        = "../host_service"
  kind          = "proxmox"
  config_json   = jsonencode({ platform_cidr = var.platform_cidr })
  change_tokens = [system_file.startup_guard.md5sum]
}

variable "kind" {
  type = string
  validation {
    condition     = contains(["proxmox", "pihole"], var.kind)
    error_message = "Only the bounded Proxmox and Pi-hole host operations are supported."
  }
}
variable "config_json" { type = string }
variable "change_tokens" {
  type    = list(string)
  default = []
}
locals {
  helper  = "/usr/local/sbin/hsp-host-config-${var.kind}"
  config  = "/etc/hsp-${var.kind}.json"
  command = "/usr/bin/python3 ${local.helper}"
}
resource "system_file" "helper" {
  path   = local.helper
  source = "${path.module}/../../scripts/host_config.py"
  mode   = "755"
  uid    = 0
  gid    = 0
}
resource "system_file" "config" {
  path    = local.config
  content = "${var.config_json}\n"
  mode    = "600"
  uid     = 0
  gid     = 0
}
resource "system_file" "unit" {
  path    = "/etc/systemd/system/hsp-${var.kind}.service"
  mode    = "644"
  uid     = 0
  gid     = 0
  content = <<-UNIT
    [Unit]
    Description=Apply bounded hsp ${var.kind} configuration
    After=network-online.target${var.kind == "proxmox" ? " pve-firewall.service" : ""}
    Wants=network-online.target${var.kind == "proxmox" ? " pve-firewall.service" : ""}
    ${var.kind == "proxmox" ? "Before=pve-guests.service" : ""}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${local.command} install ${var.kind} ${local.config}
    ExecReload=${local.command} install ${var.kind} ${local.config}
    ExecStop=${local.command} remove ${var.kind} ${local.config}

    [Install]
    WantedBy=multi-user.target
  UNIT
}
resource "terraform_data" "revision" {
  triggers_replace = var.change_tokens
  lifecycle {
    replace_triggered_by = [system_file.helper, system_file.config, system_file.unit]
  }
}
resource "system_service_systemd" "this" {
  name       = "hsp-${var.kind}"
  enabled    = true
  status     = "started"
  reload_on  = [terraform_data.revision.id]
  depends_on = [system_file.helper, system_file.config, system_file.unit]
}

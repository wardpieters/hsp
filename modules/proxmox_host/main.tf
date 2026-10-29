variable "platform_cidr" {
  type = string
  validation {
    condition = try(
      cidrhost(var.platform_cidr, 0) == split("/", var.platform_cidr)[0] &&
      tonumber(split("/", var.platform_cidr)[1]) <= 30 && (
        (can(regex("^10\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 8) ||
        (can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 12) ||
        (can(regex("^192\\.168\\.", var.platform_cidr)) && tonumber(split("/", var.platform_cidr)[1]) >= 16)
    ), false)
    error_message = "platform_cidr must be a canonical RFC1918 IPv4 network with prefix <= 30."
  }
}
locals {
  # A range change replaces the unit/service, so the old ExecStop still names
  # the old route. Connected /30 routes take precedence over the aggregate.
  routing_service = "hsp-routing-${replace(replace(var.platform_cidr, ".", "-"), "/", "-")}"
}
resource "system_file" "routing_unit" {
  path    = "/etc/systemd/system/${local.routing_service}.service"
  mode    = "644"
  uid     = 0
  gid     = 0
  content = <<-UNIT
    [Unit]
    Description=Forward and terminate unused hsp guest addresses
    Wants=network-online.target
    Requires=pve-firewall.service
    After=network-online.target pve-firewall.service
    Before=pve-guests.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/sbin/sysctl -w net.ipv4.ip_forward=1
    ExecStart=/usr/sbin/ip -4 route replace blackhole ${var.platform_cidr} metric 42760
    ExecReload=/usr/sbin/sysctl -w net.ipv4.ip_forward=1
    ExecReload=/usr/sbin/ip -4 route replace blackhole ${var.platform_cidr} metric 42760
    ExecStop=-/usr/sbin/ip -4 route del blackhole ${var.platform_cidr} metric 42760

    [Install]
    WantedBy=multi-user.target
  UNIT
}
resource "system_folder" "startup_dropin" {
  path = "/etc/systemd/system/pve-guests.service.d"
  mode = "755"
  uid  = 0
  gid  = 0
}
resource "system_file" "startup_guard" {
  path    = "${system_folder.startup_dropin.path}/hsp.conf"
  content = "[Unit]\nRequires=${local.routing_service}.service pve-firewall.service\nAfter=${local.routing_service}.service pve-firewall.service\n"
  mode    = "644"
  uid     = 0
  gid     = 0
}
resource "terraform_data" "revision" {
  lifecycle { replace_triggered_by = [system_file.routing_unit, system_file.startup_guard] }
}
resource "system_service_systemd" "routing" {
  name      = local.routing_service
  enabled   = true
  status    = "started"
  reload_on = [terraform_data.revision.id]
}
output "generation" {
  description = "Revision applied to the routing service."
  value       = terraform_data.revision.id
}

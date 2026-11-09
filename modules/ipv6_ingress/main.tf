locals {
  protected = distinct(concat(var.protected_cidrs, [var.ula_prefix, "${cidrhost("${var.public_address}/64", 0)}/64", "::/128", "::1/128", "::ffff:0:0/96", "100::/64", "fc00::/7", "fe80::/10", "ff00::/8"]))
  egress_rules = flatten([for name, e in var.egress : [for p in e.ports : {
    address = e.address, vnet_id = e.vnet_id, protocol = p.protocol,
    number  = p.protocol == "icmp" ? 58 : (p.protocol == "tcp" ? 6 : 17),
    port    = p.port
  }]])
  permissions = join("\n", concat(["H|${var.public_address}|${var.ula_prefix}"], sort(distinct(concat(
    [for f in values(var.forwards) : "D|${var.public_address}|${f.address}|${f.protocol}|${f.port}|${f.vnet_id}"],
    [for h in values(var.hairpin) : "P|${var.public_address}|${h.source_address}|${h.protocol}|${h.port}|${h.source_vnet_id}|${h.target_address}|${h.target_vnet_id}|${h.target_gateway}"],
    [for e in local.egress_rules : "E|${var.public_address}|${e.address}|${e.protocol}|${e.port == null ? "none" : tostring(e.port)}|${e.vnet_id}"]
  )))))
}
resource "system_folder" "config" {
  path = "/etc/hsp-ipv6-ingress"
  uid  = 0
  gid  = 0
  mode = "700"
}
resource "system_file" "ingress_rules" {
  path = "${system_folder.config.path}/rules.nft"
  content = templatefile("${path.module}/templates/ingress.nft.tftpl", {
    public  = var.public_address, ula = var.ula_prefix, forwards = var.forwards,
    hairpin = var.hairpin, egress = local.egress_rules, protected = local.protected, firewall_bridges = var.firewall_bridges
  })
  uid  = 0
  gid  = 0
  mode = "600"
}
resource "system_file" "ingress_permissions" {
  path    = "${system_folder.config.path}/permissions"
  content = "${local.permissions}\n"
  uid     = 0
  gid     = 0
  mode    = "600"
}
resource "system_file" "ingress_zones" {
  path    = "${system_folder.config.path}/bridge-zones"
  content = length(var.firewall_bridges) == 0 ? "" : "${join("\n", [for bridge in sort(keys(var.firewall_bridges)) : "${bridge}|${var.firewall_bridges[bridge]}"])}\n"
  uid     = 0
  gid     = 0
  mode    = "600"
}
resource "system_file" "ingress_helper" {
  path    = "${system_folder.config.path}/ingress.sh"
  content = file("${path.module}/templates/ingress.sh.tftpl")
  uid     = 0
  gid     = 0
  mode    = "700"
}
resource "system_file" "unit" {
  path    = "/etc/systemd/system/hsp-ipv6-ingress.service"
  content = <<-UNIT
    [Unit]
    Description=HSP IPv6 DNAT, internet SNAT and forwarding guard
    Requires=hsp-he-ipv6.service pve-firewall.service
    After=hsp-he-ipv6.service pve-firewall.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    Environment=PATH=/usr/sbin:/usr/bin:/sbin:/bin
    ConfigurationDirectory=hsp-ipv6-ingress
    ConfigurationDirectoryMode=0700
    RuntimeDirectory=hsp-ipv6-ingress
    RuntimeDirectoryMode=0700
    RuntimeDirectoryPreserve=yes
    ExecStart=${system_file.ingress_helper.path} start
    ExecReload=${system_file.ingress_helper.path} reload
    ExecStop=${system_file.ingress_helper.path} stop

    [Install]
    WantedBy=multi-user.target
  UNIT
  uid     = 0
  gid     = 0
  mode    = "644"
}
resource "terraform_data" "revision" {
  lifecycle { replace_triggered_by = [system_file.ingress_helper, system_file.ingress_rules, system_file.ingress_permissions, system_file.ingress_zones, system_file.unit] }
}
resource "system_service_systemd" "ingress" {
  name       = "hsp-ipv6-ingress"
  enabled    = true
  status     = "started"
  reload_on  = [terraform_data.revision.id]
  depends_on = [module.teardown]
}

# Create the gate before starting the service, so failed starts are covered.
# Destroy it after service removal but before deleting its files: inactive
# units skip ExecStop, so explicitly rerun the idempotent helper on every retry.
variable "proxmox_ssh" {
  type    = object({ host = string, user = string, port = optional(number, 22), host_key = optional(string) })
  default = null
}
resource "terraform_data" "teardown" {
  input = {
    ssh     = var.proxmox_ssh
    command = "/usr/bin/systemctl stop hsp-ipv6-ingress && ${system_file.ingress_helper.path} stop"
  }
  lifecycle {
    precondition {
      condition     = var.proxmox_ssh != null
      error_message = "HE IPv6 needs SSH agent connection settings for retryable teardown; retain them until removal completes."
    }
  }
  depends_on = [system_file.unit, system_file.ingress_rules, system_file.ingress_permissions, system_file.ingress_zones]
}

module "teardown" {
  source   = "../ssh_cleanup"
  settings = terraform_data.teardown.output
}

variable "he_ipv6" {
  type = object({
    server_ipv4     = string, local_ipv4 = string, client_ipv6 = string, server_ipv6 = string,
    routed_prefix   = string, ula_prefix = string, mtu = optional(number, 1480),
    protected_cidrs = optional(list(string), [])
  })
  default = null
  validation {
    condition = var.he_ipv6 == null ? true : try(
      can(cidrnetmask("${var.he_ipv6.server_ipv4}/32")) &&
      cidrhost("${var.he_ipv6.server_ipv4}/32", 0) == var.he_ipv6.server_ipv4 &&
      can(cidrnetmask("${var.he_ipv6.local_ipv4}/32")) &&
      strcontains(var.he_ipv6.client_ipv6, ":") && split("/", var.he_ipv6.client_ipv6)[1] == "64" &&
      cidrhost("${split("/", var.he_ipv6.client_ipv6)[0]}/3", 0) == "2000::" &&
      strcontains(var.he_ipv6.server_ipv6, ":") &&
      cidrhost("${var.he_ipv6.server_ipv6}/64", 0) == cidrhost(var.he_ipv6.client_ipv6, 0) &&
      cidrhost("${var.he_ipv6.server_ipv6}/128", 0) != cidrhost("${split("/", var.he_ipv6.client_ipv6)[0]}/128", 0) &&
      split("/", var.he_ipv6.routed_prefix)[1] == "64" &&
      cidrhost(var.he_ipv6.routed_prefix, 0) == split("/", var.he_ipv6.routed_prefix)[0] &&
      cidrhost("${split("/", var.he_ipv6.routed_prefix)[0]}/3", 0) == "2000::" &&
      cidrhost(var.he_ipv6.routed_prefix, 0) != cidrhost(var.he_ipv6.client_ipv6, 0) &&
      split("/", var.he_ipv6.ula_prefix)[1] == "48" &&
      cidrhost(var.he_ipv6.ula_prefix, 0) == split("/", var.he_ipv6.ula_prefix)[0] &&
      cidrhost("${split("/", var.he_ipv6.ula_prefix)[0]}/8", 0) == "fd00::" &&
      var.he_ipv6.mtu >= 1280 && var.he_ipv6.mtu <= 1480 && floor(var.he_ipv6.mtu) == var.he_ipv6.mtu &&
    alltrue([for c in var.he_ipv6.protected_cidrs : strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0]]), false)
    error_message = "Enabled HE requires valid IPv4 endpoints, distinct global tunnel IPv6 endpoints in one /64, a separate canonical global routed /64, canonical fd00::/8 ULA /48, integer MTU 1280..1480, IPv6 protected CIDRs."
  }
}
locals {
  he_public_address = var.he_ipv6 == null ? null : cidrhost(var.he_ipv6.routed_prefix, 2)
}
resource "system_folder" "he_helper" {
  count = var.he_ipv6 == null ? 0 : 1
  path  = "/usr/local/lib/hsp-he-ipv6"
  uid   = 0
  gid   = 0
  mode  = "700"
}
resource "system_file" "he_helper" {
  count   = var.he_ipv6 == null ? 0 : 1
  path    = "${system_folder.he_helper[0].path}/routing.sh"
  content = templatefile("${path.module}/templates/he-ipv6.sh.tftpl", merge(var.he_ipv6, { public_address = local.he_public_address }))
  uid     = 0
  gid     = 0
  mode    = "700"
}
resource "system_file" "he_sysctl" {
  count   = var.he_ipv6 == null ? 0 : 1
  path    = "/etc/sysctl.d/90-hsp-he-ipv6.conf"
  content = "# Managed by HSP; other networking may also depend on forwarding.\nnet.ipv6.conf.all.forwarding=1\n"
  uid     = 0
  gid     = 0
  mode    = "644"
}
resource "system_file" "he_unit" {
  count   = var.he_ipv6 == null ? 0 : 1
  path    = "/etc/systemd/system/hsp-he-ipv6.service"
  content = <<-UNIT
    [Unit]
    Description=HSP guarded HE IPv6 tunnel and public address
    Wants=network-online.target
    Requires=pve-firewall.service
    After=network-online.target pve-firewall.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    Environment=PATH=/usr/sbin:/usr/bin:/sbin:/bin
    RuntimeDirectory=hsp-he-ipv6
    RuntimeDirectoryMode=0700
    RuntimeDirectoryPreserve=yes
    ExecStart=${system_file.he_helper[0].path} start
    ExecReload=${system_file.he_helper[0].path} reload
    ExecStop=${system_file.he_helper[0].path} stop

    [Install]
    WantedBy=multi-user.target
  UNIT
  uid     = 0
  gid     = 0
  mode    = "644"
}
resource "terraform_data" "he_revision" {
  count = var.he_ipv6 == null ? 0 : 1
  lifecycle { replace_triggered_by = [system_file.he_helper, system_file.he_unit, system_file.he_sysctl] }
}
resource "system_service_systemd" "he_ipv6" {
  count      = var.he_ipv6 == null ? 0 : 1
  name       = "hsp-he-ipv6"
  enabled    = true
  status     = "started"
  reload_on  = [terraform_data.he_revision[0].id]
  depends_on = [module.he_teardown]
}
output "he_ipv6_status" {
  value = var.he_ipv6 == null ? null : {
    interface  = "hsp-he6", vip_interface = "hsp-vip6", public_address = local.he_public_address,
    local_ipv4 = var.he_ipv6.local_ipv4, remote_ipv4 = var.he_ipv6.server_ipv4,
    local_ipv6 = var.he_ipv6.client_ipv6, remote_ipv6 = var.he_ipv6.server_ipv6,
    ula_prefix = var.he_ipv6.ula_prefix, mtu = var.he_ipv6.mtu, route_metric = 42761
  }
}
output "he_ipv6_generation" {
  value = var.he_ipv6 == null ? null : terraform_data.he_revision[0].id
}

# Create the gate before starting the service, so failed starts are covered.
# Destroy it after service removal but before deleting its files: inactive
# units skip ExecStop, so explicitly rerun the idempotent helper on every retry.
variable "proxmox_ssh" {
  type    = object({ host = string, user = string, port = optional(number, 22), host_key = optional(string) })
  default = null
}
resource "terraform_data" "he_teardown" {
  count = var.he_ipv6 == null ? 0 : 1
  input = {
    ssh     = var.proxmox_ssh
    command = "/usr/bin/systemctl stop hsp-he-ipv6 && ${system_file.he_helper[0].path} stop"
  }
  lifecycle {
    precondition {
      condition     = var.proxmox_ssh != null
      error_message = "HE IPv6 needs SSH agent connection settings for retryable teardown; retain them until removal completes."
    }
  }
  depends_on = [system_file.he_unit, system_file.he_sysctl]
}

module "he_teardown" {
  count    = var.he_ipv6 == null ? 0 : 1
  source   = "../ssh_cleanup"
  settings = terraform_data.he_teardown[0].output
}

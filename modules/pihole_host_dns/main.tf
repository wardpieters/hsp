variable "proxy_address" {
  type = string
  validation {
    condition     = can(cidrnetmask("${var.proxy_address}/32"))
    error_message = "The wildcard proxy target must be an IPv4 address."
  }
}
# Register this dedicated file in misc.dnsmasq_lines once before relying on it.
# That host-local Pi-hole setting cannot be changed through its API.
resource "system_file" "wildcard" {
  path    = "/etc/pihole/hsp-dns.conf"
  content = "# Managed by hsp Terraform\naddress=/home.ward.nl/${var.proxy_address}\n"
  mode    = "644"
  uid     = 0
  gid     = 0
}
# A resource update due to remote file drift must trigger a restart even if the
# desired content checksum is identical to the previous successful apply.
resource "terraform_data" "revision" {
  lifecycle { replace_triggered_by = [system_file.wildcard] }
}
resource "system_service_systemd" "ftl" {
  name       = "pihole-FTL"
  status     = "started"
  restart_on = [terraform_data.revision.id]
}
output "generation" {
  description = "Wildcard file revision applied to FTL."
  value       = terraform_data.revision.id
}

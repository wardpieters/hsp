variable "proxy_address" {
  type = string
  validation {
    condition     = can(cidrnetmask("${var.proxy_address}/32"))
    error_message = "The wildcard proxy target must be an IPv4 address."
  }
}
variable "legacy_file" {
  description = "Explicitly inspected /etc/dnsmasq.d/*.conf file containing the existing wildcard, if applicable."
  type        = string
  default     = null
  validation {
    condition     = var.legacy_file == null ? true : can(regex("^/etc/dnsmasq\\.d/[a-zA-Z0-9_.-]+\\.conf$", var.legacy_file))
    error_message = "legacy_file must identify one .conf file directly inside /etc/dnsmasq.d."
  }
}
resource "system_file" "wildcard" {
  path    = "/etc/pihole/hsp-dns.conf"
  content = "# Managed by hsp Terraform\naddress=/home.ward.nl/${var.proxy_address}\n"
  mode    = "644"
  uid     = 0
  gid     = 0
}
# A resource update due to remote file drift must trigger a reload even if the
# desired content checksum is identical to the previous successful apply.
resource "terraform_data" "revision" {
  lifecycle { replace_triggered_by = [system_file.wildcard] }
}
module "service" {
  source        = "../host_service"
  kind          = "pihole"
  config_json   = jsonencode({ proxy_address = var.proxy_address, legacy_file = var.legacy_file })
  change_tokens = [terraform_data.revision.id]
  depends_on    = [system_file.wildcard]
}

variable "domain" {
  description = "DNS domain appended to each record name."
  type        = string
  nullable    = false
}
variable "records" {
  type = map(object({ mode = string, address = string, proxy_address = optional(string) }))
  validation {
    condition = alltrue([for name, r in var.records : try(
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name)) &&
      contains(["direct", "proxy", "none"], r.mode) && can(cidrnetmask("${r.address}/32")) &&
    (r.mode != "proxy" || can(cidrnetmask("${r.proxy_address}/32"))), false)])
    error_message = "Records need a single lowercase DNS label, a valid mode/address, and a proxy IPv4 target for proxy mode."
  }
}
resource "pihole_dns_record" "this" {
  for_each = { for name, r in var.records : name => r if r.mode != "none" }
  domain   = "${each.key}.${var.domain}"
  ip       = each.value.mode == "proxy" ? each.value.proxy_address : each.value.address
}
output "names" { value = [for r in pihole_dns_record.this : r.domain] }

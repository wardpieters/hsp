# Pass the SAME -var-file=../he-ipv6.tfvars to home and host-config.
variable "he_ipv6" {
  description = "Optional HE tunnel and shared public IPv6. Disabled unless explicitly enabled in both roots."
  type = object({
    enabled         = optional(bool, false)
    server_ipv4     = optional(string)
    local_ipv4      = optional(string)
    client_ipv6     = optional(string)
    server_ipv6     = optional(string)
    routed_prefix   = optional(string)
    ula_prefix      = optional(string)
    mtu             = optional(number, 1480)
    protected_cidrs = optional(list(string), [])
    port_forwards   = optional(map(object({ guest = string, port = number })), {})
  })
  default  = {}
  nullable = false
  validation {
    condition = !var.he_ipv6.enabled || try(
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
      alltrue([for c in var.he_ipv6.protected_cidrs : strcontains(c, ":") && cidrhost(c, 0) == split("/", c)[0]]) &&
      length(distinct([for f in values(var.he_ipv6.port_forwards) : f.port])) == length(var.he_ipv6.port_forwards) &&
      alltrue([for f in values(var.he_ipv6.port_forwards) :
        can(regex("^[a-z][a-z0-9-]{0,62}$", f.guest)) && f.port >= 1 && f.port <= 65535 && floor(f.port) == f.port && !contains([22, 8006], f.port)
    ]), false)
    error_message = "Enabled HE requires valid IPv4 endpoints, distinct global tunnel IPv6 endpoints in one /64, a separate canonical global routed /64, canonical fd00::/8 ULA /48, integer MTU 1280..1480, IPv6 protected CIDRs and unique valid non-management TCP ports."
  }

}
locals {
  he_ipv6_public_address = var.he_ipv6.enabled ? try(cidrhost(var.he_ipv6.routed_prefix, 2), null) : null
}

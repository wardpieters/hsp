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
  })
  default  = {}
  nullable = false
}

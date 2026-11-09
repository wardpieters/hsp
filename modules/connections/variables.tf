variable "settings" {
  description = "Shared non-secret deployment connection settings. Configure providers and credentials in the calling root."
  type = object({
    platform_cidr        = string
    proxmox_endpoint     = optional(string)
    proxmox_insecure_tls = optional(bool, false)
    pihole_url           = optional(string)
    pihole_insecure_tls  = optional(bool, false)
    proxmox_ssh = optional(object({
      host     = string
      user     = string
      port     = optional(number, 22)
      host_key = optional(string)
    }))
  })
  nullable = false
}

output "settings" {
  description = "Typed settings with defaults and endpoint checks, for root provider configuration."
  value       = var.settings
  precondition {
    condition = alltrue([
      for endpoint in [var.settings.proxmox_endpoint, var.settings.pihole_url] :
      endpoint == null ? true : can(regex("^https://[^/@?#]+/?$", endpoint))
    ])
    error_message = "Use HTTPS Proxmox and Pi-hole endpoints without embedded credentials, paths, queries, or fragments."
  }
}

output "settings" {
  description = "Typed settings with defaults and endpoint checks, for root provider configuration."
  value       = var.settings
  precondition {
    condition = (!var.require_api_endpoints || (var.settings.proxmox_endpoint != null && var.settings.pihole_url != null)) && alltrue([
      for endpoint in [var.settings.proxmox_endpoint, var.settings.pihole_url] :
      endpoint == null ? true : can(regex("^https://[^/@?#]+/?$", endpoint))
    ])
    error_message = "Use HTTPS Proxmox and Pi-hole endpoints without embedded credentials, paths, queries, or fragments."
  }
}

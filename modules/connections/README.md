# Deployment connection settings

Normalize non-secret connection settings before using them in root provider
configurations. This module contains no providers or managed resources.

Pass a `settings` object or decoded JSON containing `platform_cidr` and optional
Proxmox/Pi-hole HTTPS endpoints, TLS flags, and Proxmox SSH settings. Read the
normalized object from `module.connections.settings`. TLS flags default to
false; SSH settings default to null, and an SSH connection defaults to port 22
with no explicit host key. Optional fields retain their defaults when null.

Endpoints are checked before the settings output can be consumed by providers.
Credentials and provider configurations belong in the calling root. Inventory
and firewall validation belong in the platform and host modules.

Set `require_api_endpoints = true` when configuring API providers, so omitted or
null endpoints cannot fall back to unchecked provider environment settings.

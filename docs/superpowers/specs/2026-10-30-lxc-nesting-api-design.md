# LXC nesting through the REST API

The approved approach is a native Terraform REST resource, using `magodo/restful` 0.25.2, alongside the existing Proxmox provider. It retains non-root API authentication and the existing per-guest `nesting` input. A provider fork and a shell provisioner were considered; the user selected the REST resource.

The Proxmox container resource sets its initial nesting value on creation and ignores subsequent feature changes. A REST resource owns subsequent nesting updates and reads the config for drift. It preserves existing explicit disabled flags, rejects unrelated enabled/unsupported flags, and sends no new non-nesting flags. Managed destruction uses a feature-only PUT, never a REST DELETE of the container. Replacement follows the container resource lifecycle, even when its CT ID is reused. Existing containers need no import.

Both providers share a sensitive ephemeral `proxmox_api_token` input, requiring Terraform >=1.10. Existing token values can be passed through `TF_VAR_proxmox_api_token`; credentials do not enter resource state or plans. REST TLS verification follows `proxmox_insecure_tls`. Host routing authentication remains outside this change.

Verification uses native Terraform tests plus a local HTTP fixture with the real REST provider: enable, disable, no-op, external drift repair, preservation of explicit false flags, rejection of enabled flags, safe destruction, and replacement. No live infrastructure is applied. Feature updates may require a container restart as usual; this change does not add an automatic reboot of running containers.

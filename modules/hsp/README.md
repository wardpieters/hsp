# HSP platform module

Compose guest networking, VM/LXC provisioning, role-based firewall policy,
Pi-hole DNS, and optional shared IPv6 ingress from one inventory.

Configure providers in the calling root. Declare the provider source addresses
shown in [versions.tf](versions.tf), and pass the SSH system provider using the
`system.ingress` alias. The inventory schema is in [variables.tf](variables.tf)
and the IPv6 schema is in [ipv6.tf](ipv6.tf). Credentials belong to provider
configuration in the caller; they are not module inputs.

```hcl
module "hsp" {
  source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=COMMIT_SHA"
  providers = {
    proxmox        = proxmox
    pihole         = pihole
    restful        = restful
    system.ingress = system.ingress
  }

  # Supply inventory inputs as demonstrated by examples/home/main.tf.
}
```

Replace `COMMIT_SHA` with a published revision containing this module. The
[home example](../../examples/home) shows a complete caller, including
provider configuration and all inputs. Host routing is managed separately
through [proxmox_host](../proxmox_host), preserving its ordered deployment.

The starter targets new deployments. Existing deployments must retain their own
migration history or reviewed import plan; copying an example does not adopt
existing resources. Run `make init` and `make check` from the repository root to
validate modules and examples.

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
  source = "git::ssh://git@github.com/wardpieters/hsp.git//modules/hsp?ref=COMMIT_SHA"
  providers = {
    proxmox        = proxmox
    pihole         = pihole
    restful        = restful
    system.ingress = system.ingress
  }

  # Supply inventory inputs as demonstrated by environments/home/main.tf.
}
```

Replace `COMMIT_SHA` with a published revision containing this module. The
[home example](../../environments/home) shows a complete caller, including
provider configuration and all inputs. Host routing is managed separately
through [proxmox_host](../proxmox_host), preserving its ordered deployment.

Existing users of the example root can retain their state and use its
[moved blocks](../../environments/home/moved.tf) to adopt the module. Inspect
the plan before applying; the address migration should cause no infrastructure
changes. Run `make init` and `make check` from the repository root to validate
modules and examples.

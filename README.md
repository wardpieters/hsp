# HSP — Home Self-hosting Platform

**Terraform modules for a homelab where networking, DNS, and access rules belong together.**

Declare your VMs and unprivileged LXCs in one inventory. HSP gives each guest
its own network and static address, creates its Pi-hole DNS records, and builds
firewall rules from the services and connections you declare.

HSP targets a single **Proxmox VE 9.x** node and **Pi-hole v6**. It uses Proxmox
Simple SDN networks: each guest gets a `/30`, source IP/MAC filtering, and a
default-deny firewall policy. Your router needs one aggregate static route;
separate router VLANs are not required.

## What you can build

- **VMs and LXCs in one inventory**, with stable IDs, network slots, storage, and SSH keys.
- **Explicit service access**, using guest roles, public ports, and connections between guests.
- **Direct or proxy DNS aliases**, managed through the Pi-hole API.
- **Persistent host routing** and optional shared IPv6 ingress and egress through an HE tunnel.

HSP provisions infrastructure. Install and configure VPNs, reverse proxies,
application software, and backup schedules separately. Guests start stopped by
default so you can inspect their networking before activation.

## Use HSP in your own project

Keep your inventory, credentials, and Terraform state in your own repository.
Use HSP as a module, with provider connections configured in the calling root.
For example, the platform inventory can be as small as:

```hcl
module "hsp" {
  source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=v1.0.0"
  providers = {
    proxmox        = proxmox
    pihole         = pihole
    restful        = restful
    system.ingress = system.ingress
  }

  node_name              = "pve"
  platform_cidr          = "10.88.0.0/24"
  host_address           = "192.0.2.10"
  protected_cidrs        = ["192.0.2.0/24"]
  bootstrap_admin_cidrs  = ["192.0.2.42/32"]
  dns_servers           = ["192.0.2.53"]
  ntp_servers           = []
  domain                 = "home.example.com"
  vm_template_id         = 9000
  datastore_id           = "local-lvm"
  ssh_public_keys        = ["REPLACE_WITH_YOUR_SSH_PUBLIC_KEY"]

  guests = {
    app = {
      vm_id = 1001, slot = 1, vnet_id = "hsp1001"
      dns = { app = { mode = "direct" } }
    }
  }
}
```

This snippet shows the module interface; the [starter example](examples/README.md)
includes provider configuration, credentials, connection settings, host routing,
and outputs. Its two-guest inventory demonstrates a private proxy calling an
application on an explicitly allowed port. The in-repository examples use local
sources. The starter guide shows pinned
GitHub sources for consuming HSP from your own repository without copying its
implementation.

The addresses above are documentation examples. Replace them, the IDs, the
template/storage settings, and the SSH key before deployment. Pin a reviewed
release tag when upgrading HSP; Git sources use `?ref=`, not Terraform's `version`
argument.

## Get started

You will need Terraform **1.10 or later**, a prepared cloud-init VM template,
Proxmox API access, Pi-hole API credentials, and SSH agent access to the host.
Read the [deployment prerequisites](docs/deployment.md#prerequisites) first.

1. Copy [the starter](examples/README.md) into your own repository.
2. Fill in its shared connection settings and inventory; load credentials from your shell or secret manager.
3. Plan host routing, review it, and apply it before provisioning guests.
4. Plan the guest platform, inspect it, and follow the deployment guide for the first apply and activation.

```sh
# From your copied starter directory, after configuration and credential setup:
terraform -chdir=host-config init
terraform -chdir=host-config plan -out=hosts.tfplan
terraform -chdir=home init
terraform -chdir=home plan -parallelism=1 -out=home.tfplan
```

Host routing and the guest platform use separate states. Keep state, saved plans,
and credentials out of Git. The starter is for a new deployment; adopting
existing resources requires a reviewed import or state migration.

## Documentation

| Guide | What it covers |
| --- | --- |
| [Starter example](examples/README.md) | Copyable files, settings, credentials, and first commands |
| [Deployment](docs/deployment.md) | Prerequisites, storage, host routing, inspection, and activation |
| [Firewall roles](docs/firewall-roles.md) | Roles, service dependencies, DNS, and access policies |
| [Optional IPv6](docs/ipv6.md) | HE tunnel, shared public address, egress, and ordered cutover |
| [Verification](docs/verification.md) | Automated coverage and live acceptance limits |
| [Engineering history](docs/chapters/engineering.md) | Original designs and implementation records |

Reusable modules live in `modules/`. The main entry points are `hsp`
(guest platform), `connections` (typed connection settings), and `proxmox_host`
(host routing). Supporting modules handle individual networks, guests, DNS,
and optional IPv6 ingress.

## Development

Terraform, Make, and Node.js >=22 are required for repository checks:

```sh
make init
make check
```

The checks validate the examples and modules, run native Terraform tests with
mock providers, and exercise rendered helpers against isolated local fixtures.
They do not deploy live infrastructure. Provider versions are constrained by
the modules; example lock files make their selections reproducible.

The documentation site reads this README, the starter guide, and `docs/`:

```sh
make docs-install
make docs-start
make docs-build
```

For changes to guest or network behavior, include a focused regression test and
update the relevant guide. The Proxmox SDN applier is experimental upstream;
verify network lifecycle changes on disposable guests before a migration.

# Start a project with HSP

These examples use local modules so they exercise the current HSP checkout and
work in CI without a second repository download. You can run them here after
configuration, or copy them into your own repository and select pinned GitHub
sources as described below.

## Files

```text
infra/
  settings.json.example    # API endpoints, SSH connection, and platform CIDR
  he-ipv6.json.example     # optional HE settings; disabled by default
  .env.example             # credential placeholders
  home/                    # inventory, providers, credential inputs, outputs
  host-config/             # persistent Proxmox host routing
```

`home/main.tf` contains a private proxy and an application VM. The proxy may
reach the application on TCP 8080; the application's DNS alias points to the
proxy. Both guests remain stopped. Replace or extend that inventory for your
own services; HSP owns the input types, defaults, and validation.

## Use modules from GitHub

When copying this directory into another project, replace the local `source`
paths in `home/main.tf` and `host-config/main.tf` with these published pins:

```hcl
# connections (used by both roots)
source = "git::https://github.com/wardpieters/hsp.git//modules/connections?ref=da64fdf3b9dac3809d31f8a4d653fdcd203a7dfe"
# hsp (home root)
source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=da64fdf3b9dac3809d31f8a4d653fdcd203a7dfe"
# proxmox_host (host-config root)
source = "git::https://github.com/wardpieters/hsp.git//modules/proxmox_host?ref=da64fdf3b9dac3809d31f8a4d653fdcd203a7dfe"
```

Keep the module blocks and provider mappings; only replace their `source` values.
Use one reviewed commit across the module calls when upgrading.

## Configure

Read [the deployment prerequisites](https://github.com/wardpieters/hsp/blob/main/docs/deployment.md#prerequisites) before
using this example. It expects a Proxmox node, an existing cloud-init template,
Pi-hole, host SSH access, and your router's aggregate route.

Use a new destination directory. The following exports only committed example
files, excluding local credentials, state, plans, and provider caches. `mkdir`
refuses an existing destination before anything is copied.

```sh
# Run from a committed HSP checkout; the destination's parent must exist.
umask 077
starter_dir=/path/to/your-project/infra
mkdir "$starter_dir" &&
  git archive --format=tar HEAD:examples | tar -x -C "$starter_dir" &&
  cd "$starter_dir" &&
  cp settings.json.example settings.json &&
  cp he-ipv6.json.example he-ipv6.json &&
  cp .env.example .env
```

For a copied directory, replace its module sources as shown above before `init`.

Replace the documentation addresses and SSH user in `settings.json`. Replace
the node name, protected networks, administrator `/32`, DNS address, domain,
template ID, datastore, and guest IDs in `home/main.tf`. The starter uses the
SSH host IPv4 as `host_address`; if SSH uses a DNS name,
set `host_address` explicitly to the Proxmox LAN IPv4 in `home/main.tf`. The platform
CIDR must be unused and must not overlap your real LAN or VPN networks.

The optional paths in `config.tf` let the mock tests select the committed
templates independently of your personal files. Templates are loaded as an offline validation fallback when the personal JSON
files do not exist. Create and edit your JSON files before deployment. Keep
IPv6 disabled for the initial setup. The connection helper applies TLS and SSH
defaults and checks HTTPS endpoints; both roots use the same SSH parameters.

Put the API token, Pi-hole password, and your SSH public key list in the copied
`.env`, or export those `TF_VAR_` inputs through your normal credential setup.
The Proxmox token is sensitive and ephemeral. Load the file into your shell without printing its contents:

```sh
set -a
source .env
set +a
```

The starter includes ignore rules for credentials, Terraform working files,
state, and saved plans. It does not include secrets or state. The HSP checkout
already ignores personal JSON files under `examples/`. In your private project,
you can version your non-secret JSON settings and inventory deliberately.

## Plan and deploy

```sh
terraform -chdir=host-config init
terraform -chdir=host-config plan -out=hosts.tfplan
# Review the plan, then establish host routing:
terraform -chdir=host-config apply hosts.tfplan

terraform -chdir=home init
terraform -chdir=home plan -parallelism=1 -out=home.tfplan
# Review the plan before provisioning stopped guests:
terraform -chdir=home apply -parallelism=1 home.tfplan
terraform -chdir=home output guests
terraform -chdir=home output router_route
```

Follow the [inspection and activation procedure](https://github.com/wardpieters/hsp/blob/main/docs/deployment.md#start-inspected-guests)
before setting `started = true`. `manage_host_firewall` is off by default; set up
equivalent host protection or review/import existing host rules before enabling
full host firewall ownership. Install the reverse proxy and application software
inside the guests separately.

## Extend the example

- Add unprivileged containers with `type = "lxc"` and a downloaded `lxc_template`.
- Declare DNS aliases with direct or proxy targets.
- Add guest dependencies through `connections` and explicit outbound access through `internet_egress_ports`.
- Follow [the IPv6 guide](https://github.com/wardpieters/hsp/blob/main/docs/ipv6.md) before enabling the shared HE configuration.

Keep the Git commit pin consistent across the module calls when upgrading, then
review the plan. The examples intentionally have no migration-only `moved`
blocks: existing deployments need their own state/import plan and preserved
resource addresses. Do not apply this fresh inventory against existing guests
using an empty state.

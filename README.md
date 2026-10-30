# Home self-hosting platform

Terraform configuration for one Proxmox VE 9.x node and Pi-hole v6. Each VM or LXC gets a Simple SDN VNet, its own `/30`, a static IP, source IP/MAC filtering, and default-deny firewall rules. The EdgeRouter needs one aggregate static route and selected port forwards to guest IPs. No router VLANs are needed.

Declare a guest once in [the home inventory](environments/home/home.tfvars.example). Its DNS aliases can resolve directly to the guest or to a selected reverse proxy. Separate admin and family VPN roles generate different access rules.

See the [role and firewall reference](docs/firewall-roles.md) for every role's automatic permissions, shared defaults, rule order, and configurable exceptions.

Top-level `internet_egress_ports` allows outbound TCP/UDP ports for every guest. Each guest's own list adds its extra ports; both default to `[]`. Incoming services are configured with `public_ports`.

Guests default to `type = "vm"`, using the global `vm_template_id` (renamed from `template_id`). Set `type = "lxc"` to use the global `lxc_template` OS archive and optional `mount_points = [{ path = "/srv/data", size_gb = 50 }]`. Containers are unprivileged and use the same roles, DNS and firewall rules. See [LXC configuration and storage](docs/deployment.md#lxc-guests-and-storage) for the full example, backup behavior, and migration notes. The current `/24` supports 64 guests total across both types.

For example, inside a guest declaration:

```hcl
dns = {
  cloud      = { mode = "proxy", proxy_name = "proxy-private" }
  cloud-host = { mode = "direct" }
}
```

The `dns_records` module creates `cloud.home.ward.nl` pointing to the declared private proxy and `cloud-host.home.ward.nl` pointing to this guest, using Pi-hole's local DNS API. Every desired name is explicit; no wildcard, Pi-hole host file, or Pi-hole SSH access is needed.

| Configuration | Resources |
| --- | --- |
| `environments/home` | SDN, VMs and LXCs, firewalls, and per-guest Pi-hole DNS records |
| `environments/host-config` | Persistent Proxmox host routing, using Terraform's SSH file/service provider |
| `modules/` | Reusable network, guest, DNS, and host configuration modules |

Deploy using ordinary Terraform commands, after filling in the private variables and completing the prerequisites in the [deployment guide](docs/deployment.md):

```sh
terraform -chdir=environments/home init
terraform -chdir=environments/home plan -var-file=home.tfvars -parallelism=1 -out=home.tfplan
terraform -chdir=environments/home apply -parallelism=1 home.tfplan
```

Guests default to stopped. Inspect their networking and firewall enforcement, then set `started = true` in a second apply.

Local validation and mock-provider tests require only Terraform and Make:

```sh
make init
make check
```

Providers are pinned to `bpg/proxmox` 0.118.1, `lukaspustina/pihole` 0.3.1, and `neuspaces/system` 0.5.0. Terraform >=1.9 is required; checks use Terraform 1.14.8. The BPG SDN applier is marked experimental by its maintainer, so verify its lifecycle on disposable guests before migration.

This provisions infrastructure. VPN, reverse proxy, application software, and existing guest migration are separate work. Application containers can also run inside the managed VMs. Keep state, plans, passwords, and private variables out of Git.

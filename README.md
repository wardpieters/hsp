# Home self-hosting platform

Terraform infrastructure for one Proxmox VE 9.x node and Pi-hole v6. Proxmox owns all internal networks and routing. Each VM receives its own Simple SDN VNet and `/30`, a static address, source IP/MAC filtering, and default-deny firewall policy. The EdgeRouter needs one static route and selected direct-to-guest port forwards; no router VLANs are involved.

The implementation provisions VM infrastructure and DNS. It does **not** install VPN/reverse proxy/application software or migrate existing guests. Containers can later run inside the managed VMs; native LXC support is deferred.

Start with the [deployment guide](docs/deployment.md). The [home inventory example](environments/home/home.tfvars.example) shows public/private proxies, separate admin/family VPN gateways, application dependencies, and direct/proxy DNS aliases. The [host configuration example](environments/host-config/hosts.tfvars.example) covers persistent routing and existing wildcard adoption.

```sh
make init
make check
```

Checks use mocked Terraform providers and temporary filesystem/API fixtures. They do not connect to your infrastructure. Live filtering, DNS behavior, reboot persistence, and inbound port forwards still need the acceptance checks in the guide.

| Component | Purpose |
| --- | --- |
| `environments/home` | Normal guest inventory, SDN, guest policies, DNS records, optional host firewall ownership |
| `environments/host-config` | Separate state for persistent host routing and Pi-hole wildcard configuration |
| `modules/` | Reusable networking, VM, DNS, and bounded host configuration modules |
| `scripts/hsp.py` | Reviews a private saved plan and separates stopped provisioning from verified activation |

Providers are pinned: `bpg/proxmox` 0.118.1, `lukaspustina/pihole` 0.3.1, and `neuspaces/system` 0.5.0. Terraform >=1.9 and Python >=3.9 are required; local checks were run with Terraform 1.14.8. The BPG SDN applier is explicitly marked experimental by its maintainer; this does not require Proxmox's experimental nftables firewall. Validate SDN apply/removal on disposable guests before migration.

Keep state, plans, passwords, and private variable files out of Git. Use the guarded workflow from the guide for deployment. No live infrastructure has been applied by building this repository.

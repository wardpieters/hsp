# Deploying with Terraform

The [role and firewall reference](firewall-roles.md) lists all guest roles, automatic permissions, shared rules, and the effects of `public_ports`, `connections`, and `allow_updates`.

Each guest accepts `backup` in `home.tfvars`, defaulting to `true`. Set `backup = false` inside a guest's entry to exclude its managed `scsi0` disk from Proxmox backups. Backup-job schedules and any separate configuration-only backups are managed outside this configuration.

## Prerequisites

Record the real node name, VE patch version/firewall backend, host LAN IP, bridges, protected LAN/VPN ranges, storage, and an unused private platform range. Use the same aggregate in both environments. A `/24` holds 64 `/30` guest networks. Keep explicit slots and VM/VNet IDs stable when adding or deleting guests.

Prepare a trusted cloud-init QEMU template with one NIC, a `scsi0` root disk no larger than the requested disk, an installed QEMU agent, SSH key access, and locked password authentication. Inspect a stopped clone for inherited hooks, extra NICs, passthrough, or custom snippets before starting it.

Back up Proxmox network/SDN/firewall configuration and Pi-hole configuration. Preserve Proxmox console access during the rollout. Terraform does not automatically adopt existing guests, firewall lists, or DNS records: inspect and import them using the pinned provider's supported IDs before claiming ownership.

Use HTTPS endpoints, a dedicated Proxmox API identity, and authorized Pi-hole config-write credentials. Certificate verification defaults to enabled for both APIs. Set `proxmox_insecure_tls = true` or `pihole_insecure_tls = true` in `home.tfvars` to skip verification for the corresponding API. Pi-hole application credentials may require `app_sudo`; review the needed permission explicitly. Supply secrets through your secret manager or shell session:

- `PROXMOX_VE_API_TOKEN`: the provider's `user@realm!tokenid=secret` credential.
- `TF_VAR_pihole_password`: the Pi-hole API credential.

Proxmox host routing uses SSH agent authentication and elevated file/service access. Root logins run commands directly; other users require installed, passwordless `sudo`. SSH host-key verification is disabled. Pi-hole DNS uses only its API; no Pi-hole SSH credentials or host files are required.

## Configure and initialize

```sh
umask 077
cp environments/home/home.tfvars.example environments/home/home.tfvars
cp environments/host-config/hosts.tfvars.example environments/host-config/hosts.tfvars
make init
make check
```

Replace every illustrative address, ID, SSH key, template, datastore, and NTP target. Both environments use separate state. Keep state and plans on an encrypted, backed-up workstation. Sensitive Terraform values still appear in state and saved plans. Run only one writer against Pi-hole and use `-parallelism=1` for the home environment.

Leave new guests `started = false` and `on_boot = false`. Set `manage_host_firewall = true` only after reviewing/importing the existing full node rule list and datacenter/node settings: Terraform will own those resources. Otherwise establish equivalent host protection separately. The generated policy is visible through `terraform output host_policy`. Preserve the bootstrap administrator `/32` until admin VPN access works.

## Apply Proxmox host routing

```sh
terraform -chdir=environments/host-config plan -var-file=hosts.tfvars -out=hosts.tfplan
terraform -chdir=environments/host-config apply hosts.tfplan
```

Native Terraform file/service resources install and immediately start a systemd unit on Proxmox. It enables IPv4 forwarding and maintains a metric-42760 blackhole route for the aggregate. Connected guest `/30` routes win over that aggregate, while unused addresses terminate locally. A `pve-guests.service` drop-in orders routing and `pve-firewall.service` before autostart and checks that both are active. It uses `Wants` plus separate `ExecStartPre` checks, so stopping routing does not propagate a stop into `pve-guests` and its node-wide guest shutdown action. Startup checks apply to all guests autostarted through that Proxmox service. The unit uses the host's standard `sysctl` and `ip` commands; there are no custom host scripts.

Before first activation on a running node, inspect these read-only outputs:

```sh
sysctl net.ipv4.ip_forward
ip -4 route show table all
ip -4 rule show
systemctl is-active pve-firewall proxmox-firewall
```

Confirm the aggregate is unused across existing LAN/guest/VPN networks, the established `pve-firewall` backend is already active, and forwarding between existing interfaces is permitted by your current policy. The routing unit's `Requires=pve-firewall.service` starts that service if inactive; verify this before applying. A blackhole `/24` takes precedence over broader routes even with a high metric; do not use it to cover an existing network. Changing `ip_forward` from 0 to 1 affects the whole host and resets IPv4 configuration defaults, so review existing custom sysctls and filtering before making that change. See the [kernel forwarding documentation](https://docs.kernel.org/networking/ip-sysctl.html).

Writing the unit file alone does not execute it. The service resource enables and starts it during this apply. Neither activation nor `Before=pve-guests.service` restarts existing guests. The startup drop-in takes effect on future Proxmox guest-service starts; do not manually restart `pve-guests.service` to test it. If an older `Requires`-based drop-in was already applied, update that drop-in and reload systemd before stopping/replacing the routing service.

## Declare local DNS records

Each guest's `dns` map is passed to `modules/dns_records`, which manages `pihole_dns_record` resources through Pi-hole's local DNS API. `direct` resolves to the guest IP; `proxy` resolves to a declared proxy guest (`proxy_name`) or an external proxy IP (`proxy_address`); `none` creates no record. The inventory example shows both direct and proxy aliases. Removing an alias removes its Terraform-owned record.

The configuration no longer manages a wildcard or any Pi-hole host file. Remove the obsolete `pihole_ssh` and `wildcard_proxy_address` entries if you copied an older `hosts.tfvars` example.

To migrate from the existing wildcard, first declare or import all names currently relying on it and verify their explicit records. Then back up and remove the old wildcard at its current source, validate the Pi-hole configuration, and reload it using the installed version's procedure. Terraform does not remove that existing unmanaged directive. If an earlier version of this configuration was applied, remove its `conf-file=/etc/pihole/hsp-dns.conf` include before applying a plan that deletes that file.

## Provision stopped guests

Start with a disposable VM and an unused DNS name:

```sh
terraform -chdir=environments/home plan -var-file=home.tfvars -parallelism=1 -out=home.tfplan
terraform -chdir=environments/home apply -parallelism=1 home.tfplan
terraform -chdir=environments/home output router_route
terraform -chdir=environments/home output public_forwards
```

Review the saved plan before applying it. Inspect the stopped clone's NIC, SDN bridge, assigned address, and inherited settings. Confirm firewall enablement at datacenter/node/guest/NIC levels, DROP policies, `ipfilter-net0`, MAC filtering, and effective rule order. The established firewall backend is used; VNet/FORWARD rules from the experimental nftables backend are not required.

On the EdgeRouter, add the aggregate route from `router_route` via Proxmox's existing LAN IP. Add selected port forwards from `public_forwards` to guest IPs and ports. Check the existing WAN firewall/NAT permits replies. No VLAN configuration is needed. Do not forward Proxmox management or guest SSH.

The route makes guests reachable at Layer 3 from the LAN. Host and guest firewalls enforce access restrictions. Protected/private sources are blocked before broad public-service allows, so LAN hairpin connections may be denied; use the intended VPN access.

## Start inspected guests

Set only the inspected guests to `started = true`, then repeat the normal plan/apply commands. Keep first provisioning and first start in separate applies: VM creation and its sibling firewall resources are not an atomic transaction. There is no additional automated activation guard. Set `on_boot = true` only after reboot-persistence checks pass.

Install VPN/proxy software through your normal configuration process. The admin VPN has explicit management/guest SSH access; the family VPN has HTTPS to the private proxy plus approved DNS/NTP/update access. VPN gateways must authenticate peers, prevent spoofing, and SNAT clients to their respective gateway IPs in this model. Configure reverse proxy routes and TLS separately. DNS records alone do not configure a proxy.

## Live acceptance and removal

Before migrating real services, verify:

- Unrelated guests cannot reach each other, host management, gateway management addresses, or LAN services. Test IPv6/link-local traffic and IP/MAC spoofing too.
- Explicit dependencies work only on their declared ports; approved DNS, NTP, and optional update traffic work.
- LAN clients cannot bypass restrictions through a public-service allow. Verify effective host rules, including Proxmox's implicit management allowances.
- An external EdgeRouter-forwarded connection receives replies. Check observed source addresses and SDN SNAT behavior.
- Unallocated aggregate addresses terminate locally. Host reboot restores routing and filtering before workload autostart.
- Direct/proxy DNS aliases resolve correctly; updates and deletion preserve unrelated records.
- Removing a disposable guest cleans up its DNS, firewall, subnet, and VNet, leaves no staged SDN changes, and produces a subsequent empty plan.
- Once VPNs/proxies are configured, admin and family clients have their intended distinct access.

Remove guests through a reviewed Terraform plan. Do not reuse IDs/slots until cleanup is verified. Keep the routing foundation while guests or router routes depend on it.

Stop/remove guests and router forwards/routes before dismantling host routing. The routing service removes its own aggregate route when stopped; IPv4 forwarding is left enabled because other services may depend on it.

Use the Proxmox console and your configuration backups for recovery, then reconcile Terraform state. For Pi-hole, restore the previous local configuration, validate it, and restart FTL before retrying. The shared physical LAN uplink still needs a protected, patched Proxmox host.

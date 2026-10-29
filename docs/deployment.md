# Deploying with Terraform

## Prerequisites

Record the real node name, VE patch version/firewall backend, host LAN IP, bridges, protected LAN/VPN ranges, storage, and an unused private platform range. Use the same aggregate in both environments. A `/24` holds 64 `/30` guest networks. Keep explicit slots and VM/VNet IDs stable when adding or deleting guests.

Prepare a trusted cloud-init QEMU template with one NIC, a `scsi0` root disk no larger than the requested disk, an installed QEMU agent, SSH key access, and locked password authentication. Inspect a stopped clone for inherited hooks, extra NICs, passthrough, or custom snippets before starting it.

Back up Proxmox network/SDN/firewall configuration and Pi-hole configuration. Preserve Proxmox console access during the rollout. Terraform does not automatically adopt existing guests, firewall lists, or DNS records: inspect and import them using the pinned provider's supported IDs before claiming ownership.

Use trusted HTTPS certificates for both APIs, a dedicated Proxmox API identity, and authorized Pi-hole config-write credentials. Pi-hole application credentials may require `app_sudo`; review the needed permission explicitly. Supply secrets through your secret manager or shell session:

- `PROXMOX_VE_API_TOKEN`: the provider's `user@realm!tokenid=secret` credential.
- `TF_VAR_pihole_password`: the Pi-hole API credential.

Host configuration uses SSH with independently verified host keys, an SSH agent, and elevated file/service access. No interpreter or custom deployment executable is needed on either host.

## Configure and initialize

```sh
umask 077
cp environments/home/home.tfvars.example environments/home/home.tfvars
cp environments/host-config/hosts.tfvars.example environments/host-config/hosts.tfvars
make init
make check
```

Replace every illustrative address, ID, SSH key, template, datastore, NTP target, and host key. Both environments use separate state. Keep state and plans on an encrypted, backed-up workstation. Sensitive Terraform values still appear in state and saved plans. Run only one writer against Pi-hole and use `-parallelism=1` for the home environment.

Leave new guests `started = false` and `on_boot = false`. Set `manage_host_firewall = true` only after reviewing/importing the existing full node rule list and datacenter/node settings: Terraform will own those resources. Otherwise establish equivalent host protection separately. The generated policy is visible through `terraform output host_policy`. Preserve the bootstrap administrator `/32` until admin VPN access works.

## Apply host routing and create the wildcard file

```sh
terraform -chdir=environments/host-config plan -var-file=hosts.tfvars -out=hosts.tfplan
terraform -chdir=environments/host-config apply hosts.tfplan
```

Native Terraform file/service resources install a systemd unit on Proxmox. It enables IPv4 forwarding and maintains a metric-42760 blackhole route for the aggregate. Connected guest `/30` routes win over that aggregate, while unused addresses terminate locally. A `pve-guests.service` drop-in requires routing and `pve-firewall.service` before autostart. The unit uses the host's standard `sysctl` and `ip` commands; there are no custom host scripts.

Terraform also creates `/etc/pihole/hsp-dns.conf` with the wildcard target supplied in `hosts.tfvars`. Preserve the existing proxy address for the initial adoption.

## Adopt the existing Pi-hole wildcard once

Pi-hole's `misc.dnsmasq_lines` cannot be changed through its API. Register the dedicated file locally once, after Terraform has created it. Subsequent wildcard target changes use the file resource, and declared guest DNS names use API resources. See the [Pi-hole configuration reference](https://docs.pi-hole.net/ftldns/configfile/#dnsmasq_lines).

1. Inspect `/etc/pihole/pihole.toml`, `/etc/dnsmasq.d`, and any custom includes to locate the existing `home.ward.nl` wildcard. Back up its actual source and `pihole.toml` locally on the host.
2. In the existing `[misc]` section of `pihole.toml`, add `"conf-file=/etc/pihole/hsp-dns.conf"` to the `dnsmasq_lines` array. Preserve all unrelated array entries. Replace the old matching wildcard directive in that array, or remove just that directive from its original included file. Retain exactly one wildcard owner.
3. Run `sudo pihole-FTL dnsmasq-test`. If it succeeds, run `sudo systemctl restart pihole-FTL` and query a wildcard name. Restore the backed-up configuration if validation fails.

The module manages the dedicated file and restarts FTL on later file changes or repairs. It does not edit the rest of `pihole.toml`, migrate legacy directives, or provide automatic rollback. A restart briefly interrupts DNS.

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
- Direct/proxy DNS aliases override the wildcard correctly; updates and deletion preserve unrelated records.
- Removing a disposable guest cleans up its DNS, firewall, subnet, and VNet, leaves no staged SDN changes, and produces a subsequent empty plan.
- Once VPNs/proxies are configured, admin and family clients have their intended distinct access.

Remove guests through a reviewed Terraform plan. Do not reuse IDs/slots until cleanup is verified. Keep the routing foundation while guests or router routes depend on it.

Before removing the wildcard module, remove its `conf-file=` include locally or replace it with your intended DNS configuration, validate, and restart FTL. Deleting the file while leaving a required include would break DNS. Stop/remove guests and router forwards/routes before dismantling host routing. The routing service removes its own aggregate route when stopped; IPv4 forwarding is left enabled because other services may depend on it.

Use the Proxmox console and your configuration backups for recovery, then reconcile Terraform state. For Pi-hole, restore the previous local configuration, validate it, and restart FTL before retrying. The shared physical LAN uplink still needs a protected, patched Proxmox host.

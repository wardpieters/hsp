# Deploying the infrastructure

## 1. Inventory the existing systems

Record the real node name and VE patch version, existing bridge configuration, host LAN IP, LAN/management/guest/VPN ranges, available storage, and an unused private platform range. Slots are explicit and permanent; do not renumber them when deleting guests. A `/24` holds 64 `/30` networks.

Use a trusted cloud-init QEMU template with one ordinary NIC, a `scsi0` root disk no larger than the requested size, an installed QEMU agent, and no passthrough, extra interfaces, custom cloud-init snippets, or VM hooks. Use SSH keys and a password-locked cloud image. Clone handling depends on the real template, so inspect a stopped disposable clone before activation. Debian/Ubuntu cloud images need to be prepared as a template first; image creation is not automated here.

Back up `/etc/pve/sdn`, `/etc/network/interfaces*`, and the datacenter/node firewall configuration through your normal secure backup process. Export existing guest/firewall/DNS inventory. Retain direct Proxmox console access for recovery. Read the existing node ruleset before opting into Terraform ownership: that resource manages the **entire** node rule list.

On Pi-hole, record its core/FTL component versions and inspect the source of `*.home.ward.nl`. Preserve its current proxy IP for initial adoption. The implementation handles the usual `misc.dnsmasq_lines` directive or an explicitly selected `/etc/dnsmasq.d/*.conf` file. A different owner/include mechanism needs inspection and an explicit migration decision. It refuses ambiguous or conflicting wildcard targets.

## 2. Credentials and trusted connections

Create a dedicated Proxmox API user/token, scoped to the node, intended VM IDs/pool, storage, SDN objects, and firewall operations. Grant only the privileges required by the selected provider operations; SDN apply/host firewall bootstrap may need a separate elevated operator. Consult the pinned provider documentation rather than copy a broad Administrator role. This repository does not create its own credentials.

Use valid HTTPS certificates or a trusted private CA for Proxmox and Pi-hole. Neither provider disables TLS verification. The activation helper uses Python's default trust store; configure that store/`SSL_CERT_FILE` for your CA as well. Verify SSH host keys separately and load the operator's SSH key into an agent. Host configuration requires elevated writes to the named config/unit/helper files; never grant those credentials to application VMs.

Set these in your shell or secret-manager session, without putting their values in shell history or this repository:

- `PROXMOX_VE_API_TOKEN`: `user@realm!tokenid=secret`, consumed by the provider and activation check.
- `TF_VAR_pihole_password`: an authorized Pi-hole configuration-write credential. Pi-hole v6 application credentials may require broader `app_sudo` privileges; the code does not enable that setting. Review and configure write permission deliberately, then test with a disposable DNS name.
- `HSP_PROXMOX_SSH`: the verified SSH target such as `terraform@pve.home.ward.nl`, used for read-only routing/firewall preflight during activation. Ensure OpenSSH's known-host entry is verified too.

Use local state on an encrypted, backed-up workstation initially. Run `umask 077` before Terraform. Both environments have independent state; never copy one environment's state onto the other. Sensitive markings redact output but do not encrypt state. Do not run two Terraform writers against the same Pi-hole; the workflow uses `-parallelism=1` within a run.

## 3. Prepare private configuration and initialize

```sh
umask 077
cp environments/home/home.tfvars.example environments/home/home.tfvars
cp environments/host-config/hosts.tfvars.example environments/host-config/hosts.tfvars
make init
make check
```

Replace **all** example addresses, IDs, storage, template, SSH public key, NTP targets, SSH host keys, and protected ranges. The examples are illustrative and are not auto-loaded. Use the same platform aggregate in both environments. Include real VPN/remote networks in the overlap inventory. The protected network list must include the Proxmox LAN address.

Initially leave every guest `started = false` and `on_boot = false`. Set `manage_host_firewall = true` only after reviewing and, where required, importing the existing datacenter/node settings and full node rule list. Preserve your current runner address in `bootstrap_admin_cidrs`. If management is maintained outside Terraform, activation still requires its live rules to exactly match the generated host policy.

## 4. Apply the bounded host configuration

Review this separate plan before accepting its changes:

```sh
python3 scripts/hsp.py plan --directory environments/host-config --var-file environments/host-config/hosts.tfvars
python3 scripts/hsp.py apply --directory environments/host-config --var-file environments/host-config/hosts.tfvars
```

The Proxmox side installs an idempotent service that enables IPv4 forwarding and a metric-42760 blackhole route for the aggregate. Connected `/30` routes win over that aggregate. A `pve-guests.service` drop-in requires the host configuration and established `pve-firewall` service before guest autostart. It does not add host DNAT, change the physical bridge, or enable nftables. Inspect existing startup dependencies before applying this drop-in.

The Pi-hole side manages `/etc/pihole/hsp-dns.conf`, registers only that file, preserves unrelated dnsmasq settings, validates the combined configuration, then restarts Pi-hole FTL. This causes a brief DNS service interruption. It keeps a local backup of `pihole.toml` and a last-good managed file, and restores them if validation/reload fails. It does not send the full Pi-hole config or backup to Terraform state.

If the wildcard lives in `/etc/dnsmasq.d`, set `wildcard_legacy_file` to the inspected file. The helper removes only its matching wildcard directive after backing up the source content. It refuses shared multi-domain directives and unrelated/conflicting owners. Inspect retained `conf-file=`/`conf-dir=` includes too; the helper does not claim to discover every custom include graph automatically.

Provider read-back detects drift in the managed file. Generation resources trigger a validated service reload even if a drift repair restores the same desired checksum. Host helpers are Linux/systemd programs; their privileged lifecycle has been tested with temporary fixtures and schema validation, not on your actual Pi-hole instance.

## 5. Provision stopped guests and inspect policy

Start with a disposable VM and a new, unused DNS label. Do not claim an existing label until it is inspected/imported.

```sh
python3 scripts/hsp.py plan --var-file environments/home/home.tfvars
python3 scripts/hsp.py apply --var-file environments/home/home.tfvars
terraform -chdir=environments/home output router_route
terraform -chdir=environments/home output public_forwards
```

The wrapper prints Terraform's human-readable plan, inspects the JSON privately, and asks you to type `apply` before applying that exact saved artifact. `--yes` explicitly skips that prompt for an authorized automation. Temporary plan files are kept under a mode-700 directory and removed afterwards. New or replacement VMs requesting `started` or `on_boot` are rejected. Direct `terraform apply` bypasses this guard; it is not the deployment workflow.

Check the stopped clone has only the intended NIC and no inherited hooks/passthrough/snippets. Check datacenter, node, VM and NIC firewall enable flags, `ipfilter-net0`, input/output DROP policies, and the generated rules. Host rules are staged before Terraform enables the datacenter/node firewall. Keep the temporary bootstrap source and console access until the admin VPN works.

On the EdgeRouter, add the single route shown by `router_route`: destination is the platform aggregate and next hop is Proxmox's **existing LAN IP**. No VLAN configuration is needed. Add only selected public port forwards to the guest IP/port shown by `public_forwards`. Verify the existing WAN firewall/NAT policy supports those flows. Do not port-forward Proxmox management or guest SSH.

The static route also makes guests routable from the LAN; guest and host rules must enforce the intended restrictions. Public ingress rules block protected/private sources before the broad public allow. LAN hairpin connections may therefore be denied intentionally; use the appropriate VPN access.

## 6. Activate separately

After the stopped-provision apply is converged, change only selected existing guests to `started = true`. Optionally set `on_boot = true` after reboot-persistence testing. Do not add new guests or change policy in the activation plan.

```sh
python3 scripts/hsp.py activate --var-file environments/home/home.tfvars
```

Activation requires the enabled established firewall backend, verified host aggregate routing/forwarding, and exact live host/VM policy. It checks actual NIC count/bridge, cloud-init IPv4 address, source IP filtering, and rule order. API/SSH failure blocks activation. It rejects policy/network changes in the same apply, so first provision those changes with guests stopped, then activate. Existing unrelated running guests do not block adding a new stopped guest.

This verifies configuration, not actual packet reachability. It cannot prove that a guest or another administrator will never change state between check and apply. Console recovery and live packet tests remain necessary.

Configure the VPN/proxy software through the Proxmox console or your established configuration process. The admin VPN gateway has explicit host management/guest SSH access. The family VPN gateway has only approved DNS/NTP/update access and HTTPS to the private proxy. VPN software must authenticate peers, prevent peer spoofing, and SNAT clients to the correct gateway address for this initial routing model. Separate public/private proxies prevent a shared HTTPS listener from accidentally exposing private hostnames. Configure proxy backends and TLS separately; DNS does not create routes in the proxy.

## 7. Import, change, and remove resources

Terraform owns only declared guest DNS records. The existing wildcard continues to resolve unknown names to the original proxy until you explicitly change its target. Explicit direct/proxy records must override that wildcard in live tests. Updating a DNS alias must remove its obsolete address; test this with the pinned Pi-hole provider before adopting production records. Other tools must not concurrently rewrite the same Pi-hole config arrays.

Use `terraform import` only after mapping an existing resource to its exact address and checking the pinned provider's supported import ID. For example, the wildcard file can be imported at `module.pihole.system_file.wildcard` in the host-config environment; avoid `:content` imports of full configuration files. Do not assume every existing guest/template is compatible with the new VM module. Never remove unrelated records to make an import succeed.

For deletion, inspect the normal guarded plan. Removing a declared guest removes its owned DNS, firewall resources, subnet and VNet. Never reuse an occupied slot or VM ID before cleanup is verified. BPG labels the SDN applier experimental: verify both additions and deletions on the actual pinned provider, and check for pending SDN changes after removal.

Destroying host configuration stops its helper service first, unregistering the wildcard include or deleting only its own blackhole route. It does not restore the original wildcard as an unmanaged directive or disable IPv4 forwarding that other systems may need. Do not destroy the routing foundation while guests or router routes still depend on it. For full teardown, stop/remove guests, remove router forwards/route, then remove host configuration after reviewing DNS consequences. No blanket destroy command is provided.

## 8. Live acceptance and recovery

Before migrating a real service, verify:

- Guest-to-guest, guest-to-host (including each gateway address), and guest-to-LAN connections fail unless explicitly allowed. Repeat IPv6/link-local checks and IP/MAC spoof attempts.
- A declared proxy/backend dependency works only on its selected port. Approved DNS TCP/UDP 53, NTP, and optional updates work; Pi-hole's admin UI stays inaccessible from ordinary guests.
- LAN clients cannot use a guest's public allow rule to bypass the protected-source block. Verify host rules override any Proxmox implicit management allowance on your exact version.
- An actual external connection through EdgeRouter DNAT receives replies. Record the source address seen by the guest and check SDN SNAT has not changed internal identity assumptions.
- Unallocated aggregate addresses terminate at Proxmox rather than loop back to the router.
- Direct/proxy DNS aliases, exact-name overrides, updates and deletion behave correctly and preserve unrelated entries.
- Removing a disposable VM leaves no pending SDN configuration; the next plan is empty.
- A host reboot restores routing and firewall enforcement before workload autostart. Only then enable `on_boot` for real workloads.
- Once the services are installed, admin VPN users can administer intended resources, family users reach only the approved private applications, and family users cannot use the private proxy to reach admin/public-only hostnames.

If networking/firewall changes interrupt management, use the Proxmox console to restore the exported configuration, then reconcile Terraform state rather than blindly reapplying. For Pi-hole, retain the root-readable backup and last-good file; inspect the reported helper failure, restore the previous configuration if necessary, run its supported dnsmasq check, and restart FTL. A failed apply must be investigated before retrying.

The shared physical uplink remains on your LAN. These policies do not create physical protection from hostile Layer 2 LAN traffic. Keep host management protected and patched; separate physical networks can be a later project if that threat becomes relevant.

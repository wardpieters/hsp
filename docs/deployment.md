# Deploying with Terraform

The [role and firewall reference](firewall-roles.md) lists all guest roles, automatic permissions, shared rules, and the effects of `public_ports`, `connections`, and `internet_egress_ports`.

VM guests accept `backup` in `home.tfvars`, defaulting to `true`. Set `backup = false` inside a VM's entry to exclude its managed `scsi0` disk from Proxmox backups. Extra VM disks each have their own `backup` flag, defaulting to `true` independently of the root disk. LXC root filesystems follow backup-job selection and reject the guest-level flag when false; extra mount volumes have their own backup flags. Backup-job schedules and any separate configuration-only backups are managed outside this configuration.

Top-level `internet_egress_ports` applies to every VM and LXC and is combined with each guest's own list; both default to `[]`. Declare shared TCP/UDP destination ports or portless `{ protocol = "icmp" }` entries globally and add guest-specific permissions inside guest entries. ICMP allows IPv4 traffic outside protected networks, including ping. The example allows global UDP 123 for Debian NTP pools and uses `ntp_servers = []` to remove fixed-IP NTP exceptions. Replace the former `allow_updates` flag with explicit egress entries. Approved DNS/NTP, declared dependencies, and replies to permitted inbound connections remain available independently. See the [outbound port examples](firewall-roles.md#outbound-internet-ports).

The optional top-level `http_proxy_name` selects a shared HTTP forward proxy. The example's `http-proxy` VM has outbound TCP 80/443, and every other declared VM receives TCP 3128 access to it. Install Squid after provisioning and configure clients to use its proxy URL; see the [shared proxy reference](firewall-roles.md#shared-http-forward-proxy).

After starting a Debian guest, follow [Debian guest setup](debian-setup.md) to configure the login environment, APT, and Docker Engine to use the shared proxy, including Docker log rotation and access checks.

Set top-level `service_access_cidrs` to trusted LAN subnets for direct HTTPS access to the guest selected by `private_proxy_name`. It defaults to `[]` and grants only TCP 443 to that private proxy. Squid and management access are separate; see [LAN access to private services](firewall-roles.md#lan-access-to-private-services).

## Prerequisites

Record the real node name, VE patch version/firewall backend, host LAN IP, bridges, protected LAN/VPN ranges, storage, and an unused private platform range. Use the same aggregate in both environments. A `/24` holds 64 `/30` guest networks. Keep explicit slots and VM/VNet IDs stable when adding or deleting guests.

Prepare a trusted cloud-init QEMU template with one NIC, a `scsi0` root disk no larger than the requested disk, an installed QEMU agent, SSH key access, and locked password authentication. Inspect a stopped clone for inherited hooks, extra NICs, passthrough, or custom snippets before starting it.

Back up Proxmox network/SDN/firewall configuration and Pi-hole configuration. Preserve Proxmox console access during the rollout. Terraform does not automatically adopt existing guests, firewall lists, or DNS records: inspect and import them using the pinned provider's supported IDs before claiming ownership.

Use HTTPS endpoints, a dedicated Proxmox API identity, and authorized Pi-hole config-write credentials. Certificate verification defaults to enabled for both APIs. Set `proxmox_insecure_tls = true` or `pihole_insecure_tls = true` in `home.tfvars` to skip verification for the corresponding API. Pi-hole application credentials may require `app_sudo`; review the needed permission explicitly. Supply secrets through your secret manager or shell session:

- `TF_VAR_proxmox_api_token`: the shared `user@realm!tokenid=secret` credential for the Proxmox and REST providers. This input is sensitive and ephemeral (Terraform >=1.10), so its value is excluded from resource state and saved plans. The identity and token need `VM.Allocate` on managed LXCs for nesting updates, in addition to their existing guest-management permissions.
- `TF_VAR_pihole_password`: the Pi-hole API credential.

If your shell setup already exports `PROXMOX_VE_API_TOKEN`, reuse that token with `export TF_VAR_proxmox_api_token="$PROXMOX_VE_API_TOKEN"`. Both providers then use the same credential. Keep this mapping in your existing environment/secret-loading setup; do not add the token to tfvars. Run `make init` after updating to install the additional pinned REST provider.

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

## Extra VM disks

For VM guests, `disk_gb` sizes the root disk at `scsi0`. Use `extra_disks`
inside a guest's entry for separate data disks; `mount_points` is LXC-only.
For example, inside `guests`:

```hcl
cloud = {
  vm_id = 1004, slot = 4, vnet_id = "hsp114"
  disk_gb = 16
  ssd = true # SSD emulation for the scsi0 root disk.
  extra_disks = {
    scsi1 = { size_gb = 100, ssd = true }
    scsi2 = { size_gb = 8, datastore_id = "fast-lvm", backup = false }
  }
}
```

Keys must be `scsi1` through `scsi30`; `scsi0` is reserved for the root disk.
Use a template with its cloud-init drive at `ide2` and no data disks occupying
the requested SCSI interfaces. Each disk requires a positive integer
`size_gb` in GiB. Omit `datastore_id` to use the guest's datastore or supply a
Proxmox storage ID. Host paths, physical disk passthrough and existing-volume
references are not supported. The map defaults to `{}` and is VM-only.

Guest-level `ssd` controls SSD emulation for the boot/root disk at `scsi0`.
Set `ssd` separately inside each extra disk to control its emulation flag.
Both default to `false` independently: `ssd = true` on the guest does not
enable it for extra disks. This flag changes how the disk is presented to
the VM; it does not select SSD-backed storage or change the datastore.
LXC root filesystems do not support this flag; enabling it on an LXC guest
is rejected.

Each disk's `backup` defaults to `true`, even when the guest has
`backup = false` for its root disk. Terraform allocates and attaches these
volumes using the pinned provider's [VM disk blocks](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_vm.md#argument-reference).
Partition, format and mount new disks inside the VM separately. Identify the
new, empty disk with `lsblk -f` before formatting it, and use its filesystem
UUID in `/etc/fstab` for a persistent mount such as `/srv/data`.

Keep existing interface keys stable when adding disks. Review resizing,
renaming keys, removing disks and destroying guests carefully in the plan;
storage data is not automatically retained by this module. Back up data
before making storage changes. No automatic guest formatting or mounting is
performed.

## LXC guests and storage

Keep VM and container entries together in `guests`. Omitting `type` selects a VM. Set the renamed global `vm_template_id` to your existing QEMU template ID; it is required only when VM entries exist. For containers, configure a downloaded OS template archive at the top level:

```hcl
vm_template_id = 9000
lxc_template = {
  file_id = "local:vztmpl/REPLACE_WITH_DOWNLOADED_TEMPLATE.tar.zst"
  os_type = "debian"
}
```

Use the exact archive ID shown by `pveam list local` (or your template datastore). Terraform references that existing archive; it does not download one. `os_type` defaults to `debian` and must match its supported distribution. `unmanaged` is excluded so Proxmox can configure the container's networking. A VM-only inventory may leave `lxc_template = null`; an all-LXC inventory may omit `vm_template_id`.

For example, add this entry inside `guests`, choosing an unused ID, slot and VNet:

```hcl
files = {
  type       = "lxc"
  vm_id      = 1008
  slot       = 8
  vnet_id    = "hsp1008"
  cores      = 1
  memory_mb  = 512
  disk_gb    = 8
  mount_points = [
    { path = "/srv/data", size_gb = 50 },
    { path = "/srv/cache", size_gb = 8, datastore_id = "local-lvm", backup = false },
  ]
  dns = { files = { mode = "direct" } }
}
```

`vm_id` remains the shared Proxmox VM/CT identifier. IDs and slots are unique across both types. Every guest has its own VNet and `/30`; a `/24` supports 64 guests total, including both VMs and LXCs. Roles, DNS aliases, global/per-guest egress, bootstrap SSH, LAN HTTPS, and explicit dependencies work across types.

`disk_gb` sizes the root filesystem. Each optional mount allocates a new managed volume with a positive integer `size_gb` in GiB and a unique, normalized absolute `path` inside the container. Paths cannot be `/`, contain empty/`.`/`..` components, whitespace, commas, equals, or backslashes. Mounts default to the global `datastore_id`, with an optional storage-ID override. Host bind paths and existing volume references are excluded. These options map to the pinned provider's [container resource](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_container.md).

Mounts are ordered as `mp0`, `mp1`, etc. Append new entries and preserve existing order. Review resizing, reordering, removal, and guest destruction carefully; storage data is not automatically retained by this module. Deletion of unrelated/unreferenced disks is disabled. Choose storage that supports LXC rootfs and managed container volumes.

Each mount's `backup` defaults to `true`, overriding the provider's false default. LXC root filesystems have no equivalent to the VM disk backup toggle: guest-level `backup = false` is rejected. To omit an entire LXC from backups, exclude its ID in the separately managed backup job. A mount's `backup = false` excludes that extra volume only. See [Proxmox container backup behavior](https://github.com/proxmox/pve-docs/blob/master/vzdump.adoc).

Containers are unprivileged. Set `nesting = true` inside an LXC guest's entry to enable Proxmox `nesting=1`; it defaults to `false` and is rejected on VMs. FUSE, keyctl and mknod remain disabled. Containers share the host kernel, so their host isolation differs from a VM even though network policy is shared. Enabling nesting does not install or configure application/container software. Raw host mounts and cgroup2 rules use the separate SSH inputs below; custom ID maps remain outside this module. The supplied SSH keys are installed for `root`, rather than creating the VM's `ward` user. Use `ssh root@<container-IP>` when an SSH server is available, or bootstrap through the Proxmox console. New containers stay stopped without autostart until inspected and explicitly activated.

Nesting is managed automatically by a native `magodo/restful` resource using the same non-root API token. The Proxmox resource sets initial features at container creation, then ignores feature updates; the REST resource owns subsequent nesting changes and detects external drift. This avoids the pinned Proxmox provider's root-only update serialization. It sends only `nesting=1` or `nesting=0`, preserving any already-present `fuse=0`, `keyctl=0` and `mknod=0` flags because Proxmox distinguishes omitted flags from explicit zeros. Enabled or unsupported unrelated feature flags cause a clear error before any REST write. See the [provider implementation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/proxmoxtf/resource/container/container.go#L2551-L2623) and [Proxmox permission check](https://github.com/proxmox/pve-container/blob/master/src/PVE/LXC.pm).

Existing containers acquire REST feature ownership on the next apply without an import. The additional resource is replaced when the container is replaced, including reuse of the same CT ID. Its destroy action sends a feature-only PUT disabling nesting before container deletion; it never deletes the container through the REST provider. TLS verification follows `proxmox_insecure_tls`. No root authentication, host commands, scripts or per-container manual API requests are required. Proxmox may stage feature changes on running containers until their next restart; this module does not automatically reboot them.

For existing deployments, rename `template_id` to `vm_template_id` in your private tfvars. A `moved` block migrates the existing VM resource address to its new `[0]` index without recreating it; existing network, firewall and DNS resource addresses remain. Inspect the plan for moves rather than replacements. Changing an existing entry's `type` does not convert its filesystem: create a new guest with a new ID/slot and migrate the workload/data separately. Changing a template can require replacement.

### Raw LXC mounts and cgroups over SSH

Use `lxc_mounts` for raw `lxc.mount.entry` values and `lxc_cgroups` for cgroup2 key suffixes mapped to lists of values. Both are optional, default empty and are LXC-only. These inputs edit the Proxmox container configuration through SSH because the API cannot write arbitrary `lxc.*` entries. Existing API authentication is unchanged; no root API password or additional provider is required.

Set host access at the top level of `home.tfvars` (this is separate from `environments/host-config/hosts.tfvars`):

```hcl
proxmox_ssh = {
  host = "192.168.50.10"
  user = "root"
  # port = 22
  # host_key = "ssh-ed25519 AAAA..." # Supply the real host key to verify the server.
}
```

Load a client SSH key authorized on the Proxmox host into your local SSH agent before applying. The connection must reach the host identified by `node_name`; the helper checks that the node matches. A non-root SSH user needs passwordless sudo for the Perl helper. No SSH connection is attempted for guests with empty raw inputs. Omitting `host_key` leaves host-key verification disabled, consistent with the existing host-routing setup.

For the requested GPU mounts, add these fields inside an LXC guest entry:

```hcl
lxc_mounts = [
  "/dev/dri dev/dri none bind,optional,create=dir",
  "/dev/dri/card0 dev/dri/card0 none bind,optional,create=file",
  "/dev/dri/renderD128 dev/renderD128 none bind,optional,create=file",
]
lxc_cgroups = {
  "devices.allow" = ["c 226:0 rwm", "c 226:128 rwm", "c 29:0 rwm"]
}
```

This writes three `lxc.mount.entry:` lines and three `lxc.cgroup2.devices.allow:` lines. Supply lowercase cgroup keys and single-line values without surrounding whitespace, key prefixes or trailing continuation backslashes. Repeated keys are supported; duplicate key/value pairs are rejected. The render-device destination is exactly `/dev/renderD128`, as requested; use `dev/dri/renderD128` instead if your application expects `/dev/dri/renderD128`. Device nodes and their permissions must permit the intended application access. Bind mounts do not copy host device data into managed backup volumes.

The SSH helper uses Proxmox's container configuration lock and preserves unrelated settings, raw entries and snapshots. Matching existing entries are adopted; Terraform then owns those exact pairs. Input changes replace the SSH operation: its destroy step removes the previous pairs before the create step adds the desired ones. Emptying both inputs removes the managed pairs. Cleanup uses the connection saved in state, so keep the old SSH access available during changes and removal. The helper never deletes the container configuration or storage.

Create new guests stopped using the existing two-apply activation workflow. Changes to raw mounts/cgroups take effect on the next container restart; Terraform does not restart a running guest. The SSH operation runs when its inputs/helper change or its container is replaced. It does not refresh manual edits to the raw entries. To reapply after external edits, use a normal plan/apply with `-replace='module.service["files"].module.vm.terraform_data.lxc_config[0]'`, substituting the guest name. Inspect the stopped container's configuration before activation.

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

## Optional HE IPv6

Use the [IPv6 deployment guide](ipv6.md) for the default-off shared toggle, Proxmox tunnel/VIP, isolated ULA guest networks, TCP DNAT and permitted TCP/UDP/ICMP SNAT. Both roots must receive the same `-var-file=../he-ipv6.tfvars`; host-config applies first when enabling and home first when disabling. Public DNS and the old endpoint/EdgeRouter cutover remain manual. Home needs `proxmox_ssh` when HE is enabled; retain its settings through cleanup. Local DNS remains IPv4-only.

## Declare local DNS records

Set the required `domain` variable in `home.tfvars` (for example, `domain = "home.example.com"`); it has no default. Each guest's `dns` map is passed to `modules/dns_records`, which appends this domain to each alias and manages `pihole_dns_record` resources through Pi-hole's local DNS API. `direct` resolves to the guest IP; `proxy` resolves to a declared proxy guest (`proxy_name`) or an external proxy IP (`proxy_address`); `none` creates no record. The inventory example shows both direct and proxy aliases. Removing an alias removes its Terraform-owned record.

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

The route makes guests reachable at Layer 3 from the LAN. Host and guest firewalls enforce access restrictions. Set top-level `public_ports_lan_cidrs` in `home.tfvars` to allow selected LAN subnets to reach each guest's declared `public_ports`; the default `[]` keeps those LAN sources blocked. These narrow exceptions precede protected-source drops. Access through the router's public endpoint from inside the LAN also requires hairpin NAT. See the [LAN access reference](firewall-roles.md#lan-access-to-public-ports).

## Start inspected guests

Set only the inspected guests to `started = true`, then repeat the normal plan/apply commands. Keep first provisioning and first start in separate applies: VM/LXC creation and its sibling firewall resources are not an atomic transaction. There is no additional automated activation guard. Set `on_boot = true` only after reboot-persistence checks pass.

Install VPN/proxy software through your normal configuration process. The admin VPN has explicit management/guest SSH access; the family VPN has HTTPS to the private proxy plus approved DNS/NTP and any configured internet egress. VPN gateways must authenticate peers, prevent spoofing, and SNAT clients to their respective gateway IPs in this model. Configure reverse proxy routes and TLS separately. DNS records alone do not configure a proxy.

### Bootstrap guest SSH

For initial setup, add `bootstrap = true` inside the selected guest's entry in `home.tfvars`, for example `guests.vpn-admin`. This allows incoming TCP 22 from each `bootstrap_admin_cidrs` IPv4 `/32` before the guest's protected LAN block. Bootstrap defaults to `false` and applies only to the selected guest. It works with `manage_host_firewall = false` because it manages the guest firewall directly.

Apply the change through the normal plan/apply workflow. Start the inspected guest with `started = true`, ensure your workstation can route to its address using the EdgeRouter aggregate route, and connect using the configured SSH key. With `vpn-admin` in slot 0 of `10.77.0.0/24` and the default username:

```sh
ssh ward@10.77.0.2
```

Your workstation's source IP must match an entry in `bootstrap_admin_cidrs`, and the guest image must provide a running SSH server. Once VPN access works, set `bootstrap = false` and apply again to remove the bootstrap SSH rule. The administrator list continues to control the separate Proxmox host allowances when host firewall management is enabled.

LXC guests use the same bootstrap firewall flag, but their supplied keys belong to `root`. Connect as `root` rather than `ward`, or use the Proxmox console if the archive does not provide an SSH server.

## Live acceptance and removal

Before migrating real services, verify:

- Unrelated guests cannot reach each other, host management, gateway management addresses, or LAN services. Test IPv6/link-local traffic and IP/MAC spoofing too.
- Explicit guest/IP dependencies work only on their declared destination addresses and ports; approved DNS and NTP work. General internet access uses the combined global and per-guest egress ports; with both lists empty, only explicit dependencies and infrastructure exceptions remain permitted.
- Bootstrap adds SSH access only from the listed administrator `/32` addresses. Disabling it removes that exception; other guests retain their existing policies.
- Only LAN subnets in `public_ports_lan_cidrs` can use the public-port exceptions. Other ports retain their restrictions. Verify effective host rules, including Proxmox's implicit management allowances.
- LAN sources in `service_access_cidrs` can reach the selected private proxy on TCP 443. This setting must not open Squid, SSH, other private proxies, or backend VMs; removing the list removes its HTTPS exception.
- An external EdgeRouter-forwarded connection receives replies. Check observed source addresses and SDN SNAT behavior.
- Unallocated aggregate addresses terminate locally. Host reboot restores routing and filtering before workload autostart.
- Direct/proxy DNS aliases resolve correctly; updates and deletion preserve unrelated records.
- Removing a disposable guest cleans up its DNS, firewall, subnet, and VNet, leaves no staged SDN changes, and produces a subsequent empty plan.
- Repeat isolation, source-spoofing, dependency, DNS, mount ownership/size and backup checks with a disposable LXC, including VM-to-LXC and LXC-to-VM traffic.
- Once VPNs/proxies are configured, admin and family clients have their intended distinct access.

Remove guests through a reviewed Terraform plan. Do not reuse IDs/slots until cleanup is verified. Keep the routing foundation while guests or router routes depend on it.

Stop/remove guests and router forwards/routes before dismantling host routing. The routing service removes its own aggregate route when stopped; IPv4 forwarding is left enabled because other services may depend on it.

Use the Proxmox console and your configuration backups for recovery, then reconcile Terraform state. For Pi-hole, restore the previous local configuration, validate it, and restart FTL before retrying. The shared physical LAN uplink still needs a protected, patched Proxmox host.

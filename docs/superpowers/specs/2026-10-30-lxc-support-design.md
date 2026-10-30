# LXC support alongside virtual machines

## Intent and agreed scope

Add Proxmox LXC system containers to the existing Terraform platform. The user selected one shared `guests` inventory and creation from a downloaded OS template archive. Containers receive the same network isolation, firewall policy, DNS automation, and explicit connection model as VMs. Add managed storage mount points and rename the VM template input to `vm_template_id`.

This extends the earlier VM-only design. It does not deploy application software, migrate an existing VM into a container, manage backup schedules, download a particular template, or apply infrastructure changes.

## Approaches

1. **Shared inventory and policy, with a guest type selector — selected by the user.** Existing declarations default to VMs. Containers use the same identity, slot, role, and DNS fields. One firewall implementation prevents the two guest types from developing different policies.
2. **Separate VM and container inventories/modules.** This separates provisioning code, but duplicates inventory validation, cross-guest dependency wiring, and policy composition. It was not selected.

Keep the existing `module.service[...].module.vm` module path for compatibility. That leaf will provision either a VM or an LXC and retain one shared firewall implementation. The internal module name is historical; no public input depends on that name.

## Inventory interface

Each guest gains `type`, accepting `"vm"` or `"lxc"` and defaulting to `"vm"`. Keep `vm_id` as the shared Proxmox guest identifier, including for containers, consistent with the provider. VM IDs, subnet slots, VNets, and DNS aliases remain unique across both types.

Rename `template_id` to `vm_template_id` throughout the active Terraform interfaces, tests, examples, documentation, and the operator's ignored `home.tfvars`. Preserve its existing numeric value. No legacy alias is necessary. Require a valid VM template ID when any VM is declared; an all-container inventory may omit it.

Add one global `lxc_template` object, optional unless an LXC is declared:

```hcl
vm_template_id = 9000
lxc_template = {
  file_id = "local:vztmpl/REPLACE_WITH_DOWNLOADED_TEMPLATE.tar.zst"
  os_type = "debian"
}
```

`file_id` identifies an existing `vztmpl` archive on the Proxmox host. `os_type` defaults to `debian` and must be a supported managed distribution type. It is explicit so Proxmox can configure the guest's network rather than treating its filesystem as unmanaged. The builder may refine validation against the pinned provider's supported values. Do not guess a real template filename in the private inventory; leave `lxc_template = null` until the operator chooses a downloaded archive.

Illustrative guest entry, not an addition to the operator's live inventory:

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
  ]
  dns = { files = { mode = "direct" } }
}
```

## Network and firewall behavior

Every VM or LXC consumes one existing `/30` subnet and VNet, allocated by its fixed slot. The current `/24` therefore supports 64 guests total across both types. LXC gets exactly one interface and a static IPv4 address/gateway; it does not use DHCP or add a LAN bridge attachment. Router settings are unchanged.

Reuse the existing ordered firewall policy: incoming/outgoing DROP, explicit IPv6 drops, MAC/IP filtering, the canonical bare-address `ipfilter-net0` set, approved DNS/NTP, global plus per-guest internet ports, public-port LAN allowances, private-proxy LAN HTTPS access, bootstrap SSH, and role-generated and explicit dependencies. Container firewall resources must target `container_id`; VM resources continue targeting `vm_id`. Use `net0` as the firewall interface selector for both types. Proxmox's firewall validates guest selectors as `netN` and maps LXC `net0` to its host veth device; the container-internal name can remain `eth0`.

Guest roles and DNS modes work across both types, including VM-to-LXC and LXC-to-VM dependencies. Existing restrictions on the service VPN, private proxies, and management roles remain. Full policy outputs remain sensitive.

## LXC defaults and access

Create unprivileged containers, with nesting and other optional privilege-expanding features disabled. Do not add host bind mounts, device passthrough, custom ID maps, or privileged-container controls in this change. LXC shares the host kernel; equal network policy does not make its isolation boundary identical to a VM's.

Use the existing CPU, memory, root-disk, `started`, and `on_boot` inputs. Containers default to stopped and without autostart, matching the existing activation procedure. Install the supplied SSH public keys for the container's root account; the LXC provider does not create the VM's `ward` cloud-init account. Bootstrap still grants TCP 22 only from `bootstrap_admin_cidrs`; an SSH daemon must be present and configured in the chosen archive. The Proxmox console remains available for initial setup. No guest execution scripts or passwords are added.

## Mount points and backups

`mount_points` is an ordered list, default `[]`, supported only for LXC. Each entry has required `path` and positive integer `size_gb`, optional `datastore_id` defaulting to the global guest datastore, and optional `backup` defaulting to `true`. Allocate new Proxmox-managed volumes; these fields do not expose arbitrary host paths or existing volume IDs. Validate storage identifiers to exclude `/` and `:` so neither a per-mount override nor the fallback datastore can be interpreted as a bind mount or existing volume. Validate unique, normalized absolute container paths other than `/`, with no `.`/`..` components, and reject mount points on VM declarations.

The provider represents these as positional `mp0`, `mp1`, etc. Document that callers should append entries, preserve order, and inspect changes/removal carefully. Removing a mount, replacing a container, and destroying a guest are storage lifecycle operations; this feature does not promise to retain data automatically. Do not enable deletion of unrelated/unreferenced disks on container destruction.

Preserve VM `backup` behavior and its default `true`. The pinned LXC root-disk schema has no equivalent backup flag; Proxmox backs up a container's root filesystem whenever that container is selected by a backup job. Reject guest-level `backup = false` on LXC with an explanation to exclude the container in the external backup job instead, rather than silently claiming to disable its root backup. Additional mount volumes use their own `backup` flags. No backup jobs are created or changed.

## State compatibility and migration

Keep guest map keys, IDs, slots, VNets, DNS resources, and firewall resource addresses stable. Conditional VM creation adds a count index; ship a Terraform `moved` block mapping the existing unindexed VM resource to `[0]`. Test a plan against a controlled legacy-state fixture to prove that an unchanged existing VM is moved without replacement and that its firewall/SDN/DNS resources are not recreated.

Changing an existing guest's `type` is not an in-place conversion. Document a separate new-ID/new-slot migration for workloads and data; do not convert any private-inventory guest as part of implementation. Changing an LXC template may require replacement and must appear in plan review.

## Verification and delivery

The current baseline passes 68 native Terraform tests and validates all eight configurations. Add meaningful provider-mocked plans covering mixed inventories, container resource targeting, one-NIC static addressing, unprivileged/stopped defaults, mount allocation and validation, both directions of cross-type dependencies, DNS, inherited/global ports and existing role restrictions, required templates, invalid types, and legacy VM state migration. Retain all existing policy tests; do not rely only on rule-list equality.

Update deployment and firewall documentation, examples, Makefile/CI coverage if required, and the ignored private file's VM template variable name. Preserve the user's unrelated deletion in `docs/deployment.md`. Run the full suite, request code review, and commit the implementation. No live apply is authorized or necessary for this deliverable. Live LXC startup, source spoofing, routing, storage, DNS, and effective firewall checks remain documented deployment verification.

## Builder discretion and sources

The builder may choose file boundaries, local helper expressions, and validation structure while preserving the contracts above. Keep native Terraform resources and the pinned provider; no Python helpers, provisioners, or new provider dependencies are needed.

- [Pinned container resource documentation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_container.md)
- [Pinned firewall resource documentation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_firewall_rules.md)
- [Proxmox firewall interface validation and container rule generation](https://github.com/proxmox/pve-firewall/blob/master/src/PVE/Firewall.pm)
- [Proxmox container documentation](https://github.com/proxmox/pve-docs/blob/master/pct.adoc)
- [Proxmox backup documentation](https://github.com/proxmox/pve-docs/blob/master/vzdump.adoc)

# LXC mounts and cgroups over SSH

The user directs implementation of raw LXC mounts and cgroups over SSH, using `lxc_mounts` and `lxc_cgroups`. This replaces the earlier native-device proposal. Native `devN` passthrough and API-managed `mpN` mounts do not express the requested raw configuration; the API cannot write arbitrary `lxc.*` entries.

## Interface and implementation choices

Per guest, `lxc_mounts` is an ordered list of mount-entry strings (without the `lxc.mount.entry:` prefix). `lxc_cgroups` is a map of cgroup2 key suffixes to ordered lists of values, such as `"devices.allow" = ["c 226:0 rwm", "c 226:128 rwm"]`. Both default empty and are rejected for VMs. Values must be single-line and keys must be valid cgroup names.

An optional home-environment `proxmox_ssh` object supplies host, user, port and an optional host key. Authentication uses the SSH agent; non-root users require passwordless sudo. Existing API authentication stays in place.

A Terraform-managed SSH operation runs a small Perl helper using the host's Proxmox libraries and container configuration lock. It appends missing requested entries and preserves all other configuration, including snapshots. Updates first remove exact previously owned key/value pairs, then install the desired entries. Emptying the inputs or destroying the resource removes those owned pairs without deleting the container configuration. Container replacement reapplies the entries, including when its CT ID is reused. No local private keys or root passwords enter state.

This uses Terraform's built-in remote-exec provisioner, avoiding a new provider. It runs when inputs or the helper change and when the container is replaced. It does not automatically detect manual edits to the raw entries; users can explicitly replace the SSH resource to reapply them. First creation follows the existing stopped-guest workflow. Applying entries does not restart running guests; changes take effect at their next restart.

## Verification

Use native Terraform plan tests for payloads, opt-in/default behavior, VM rejection and malformed input. Run the actual Perl helper with fixture Proxmox storage/locking boundaries to verify append, idempotence, removal, preservation, wrong-node rejection and lock failures. Run the existing offline suite. No live host access or infrastructure apply is authorized or required for implementation verification. Preserve the user's unrelated work in the current feature checkout.

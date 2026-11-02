# Extra VM disks

Add the `extra_disks` interface discussed in chat so VM guests can allocate
separate managed data disks. LXC `mount_points` remains container-only.

## Interface and behavior

`extra_disks` is an optional map keyed by canonical SCSI interface, `scsi1`
through `scsi30`. `scsi0` remains the existing root disk controlled by
`disk_gb` and guest-level `backup`. Each value requires positive integer
`size_gb` in GiB and accepts `datastore_id` (default: guest datastore) and
`backup` (default: true, independent of root backup). The default is `{}`.
Nonempty values are VM-only. Storage must be a storage ID, not a host path
or existing volume. Invalid/null disk entries fail validation.

Guest-level `ssd` controls SSD emulation for the `scsi0` root disk. Each
`extra_disks` entry accepts its own independent `ssd`. Both default to false,
preserving existing provider behavior; enabling root SSD emulation does not
enable it for extra disks. Root `ssd = true` is VM-only and rejected on LXC.
SSD emulation does not select or change the backing datastore.

Pass this type unchanged through home inventory and service_vm into vm.
Render additional provider disk blocks with discard enabled, matching the
root disk. Preserve existing resource addresses and empty-input behavior.

## Approaches

The map proposed in chat and accepted by the user gives each disk an explicit
interface that survives unrelated additions/removals. An ordered list would
make interface assignment depend on position; individually hardcoded blocks
would limit per-guest configuration. Use the map. Restricting keys to SCSI
and keeping backup independent of the root setting are implementation choices.

## Scope and verification

Allocate new volumes only. Guest partitioning, formatting, mounting, physical
disk passthrough, imports, live infrastructure changes, and backup-job
scheduling are outside this change. Document lifecycle/data-loss risks and
keep interface keys stable. Test provider plans, invalid values, unchanged
root defaults, and propagation through the complete inventory path. Run
`make check` and the documentation build.

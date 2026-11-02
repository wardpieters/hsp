# Extra VM disks implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allocate per-VM data disks from the home inventory.

**Architecture:** Pass an optional interface-keyed map through home and
service_vm into vm. Retain the existing root block and add dynamic data-disk
blocks with validation at the VM module boundary.

**Tech Stack:** Terraform, bpg/proxmox 0.118.1, Terraform mock-provider tests.

**Spec:** `docs/superpowers/specs/2026-11-02-vm-extra-disks-design.md`

## Global constraints

- SCSI keys `scsi1` through `scsi30`; `scsi0` stays reserved for the root.
- Positive integer sizes in GiB; storage IDs only; extra backups default true.
- Empty map preserves existing behavior; nonempty values are VM-only.
- Preserve all pre-existing checkout edits; leave changes uncommitted for review.
- Do not apply against live infrastructure or edit private tfvars.

## Review focus

- Root backup disabled while extra backup defaults true: assert both flags.
- Sparse/out-of-order interface keys: assert values by interface, not position.
- Null disk objects/fields: validate cleanly instead of evaluating invalid values.
- Empty storage overrides and volume/host paths: reject as invalid storage IDs.
- Dropped fields in any module: inspect the full root test plan's disk blocks.

### Task 1: Implement and document additional disks

**Files:** `modules/vm/{variables,main}.tf`,
`modules/service_vm/main.tf`, `environments/home/{variables,main}.tf`,
`modules/vm/tests/disks.tftest.hcl`, `environments/home/tests/lxc.tftest.hcl`,
`environments/home/home.tfvars.example`, `README.md`, `docs/deployment.md`,
`docs/chapters/deployment.md`.

**Interfaces:** `extra_disks = map(object({ size_gb = number,
datastore_id = optional(string), backup = optional(bool, true) }))`,
default `{}`. Home and service guest objects expose the same optional field.

- [x] Add plan tests for root defaults, sparse extra disks with default/override
  storage and backup, maximum interface, invalid interfaces/sizes/storage,
  null entries, and LXC rejection; observe failures before implementation.
- [x] Add a VM extra disk to the mixed home test inventory, capture its verbose
  JSON plan, and verify it lacks the expected disk before implementation.
- [x] Add schema/forwarding and VM dynamic disks/validation per the spec.
- [x] Run targeted VM tests and inspect the mixed root plan for exact disk values.
- [x] Add working inventory example and lifecycle/guest mounting documentation.
- [x] Run `make check`, `make docs-build`, `git diff --check`, and review the
  change against the spec. Report verification limitations, if any.

### Task 2: SSD emulation for root and extra disks

**Files:** Same module, inventory, test, example and documentation files as Task 1.

**Interfaces:** Guest/module `ssd = bool`, default false. Each extra-disk
object adds `ssd = optional(bool, false)`. Root and per-disk flags are independent;
enabling root `ssd` on LXC must fail validation.

- [x] Extend the disk plan assertions for enabled root/data disks, explicit and
  default false data disks under a true root, default false root under a true
  data disk, and LXC rejection; observe the tests fail before implementation.
- [x] Add `ssd` schemas and forwarding throughout home/service_vm/vm, set each
  provider disk's SSD flag, and validate root use on LXC.
- [x] Update examples/docs to explain SSD emulation and independent false defaults.
- [x] Run targeted disk tests, inspect the mixed root plan's SSD flags, run
  `make check`, `make docs-build`, `git diff --check`, and review the change.

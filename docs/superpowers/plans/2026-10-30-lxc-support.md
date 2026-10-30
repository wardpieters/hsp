# LXC Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add isolated LXC guests and managed mount volumes to the existing Terraform inventory without replacing existing VMs.

**Architecture:** Keep `module.service[...].module.vm` and all firewall/DNS/network addresses. The leaf selects a counted VM or LXC resource and attaches the existing shared policy to the matching API endpoint. A moved block handles the VM resource's new index.

**Tech Stack:** Terraform, pinned `bpg/proxmox` 0.118.1 and Pi-hole provider, native provider-mocked tests.

**Spec:** `docs/superpowers/specs/2026-10-30-lxc-support-design.md` (approved).

## Global Constraints

- One shared `guests` inventory; `type` accepts `"vm"` or `"lxc"`, default `"vm"`.
- Keep guest IDs, slots, VNets, existing firewall resources, and DNS addresses stable.
- Global `lxc_template = { file_id, os_type }`; rename `template_id` to `vm_template_id`.
- LXC is unprivileged, stopped without autostart by default, one static `/30` interface, and no nesting or host mounts.
- Native Terraform only; no new providers, guest execution scripts, or live apply.
- Preserve the unrelated user deletion in `docs/deployment.md`; only rename the template input and add null LXC template in private tfvars.

## Review Focus

- Legacy unindexed VM state must move to `[0]` without replacement; verify with a legacy-state fixture and plan JSON (Task 1/4).
- A container firewall must use `container_id` and `net0`, not a QEMU endpoint or internal `eth0` selector (Task 1).
- Invalid mount paths/storage identifiers must not become host bind mounts, existing volumes, or ambiguous mount targets (Task 2).
- An all-LXC inventory must work without a VM template; missing LXC templates and unsupported backup disabling must fail clearly (Task 2/3).
- Mixed-type dependencies and proxy selection must retain role restrictions, global egress, and LAN service boundaries (Task 3).

### Task 1: Conditional guest provisioning and shared firewall targeting

**Files:** Modify `modules/vm/{main,variables}.tf`, `modules/vm/tests/policy.tftest.hcl`; create `modules/vm/container.tf`, `modules/vm/tests/lxc.tftest.hcl`.

**Interfaces:** Leaf inputs `guest_type: string = "vm"`, `vm_template_id: number = null`, `lxc_template: object({file_id:string,os_type:optional(string,"debian")}) = null`; existing `vm_id`, networking and policy inputs retained. Existing `vm_id` output selects the actual guest resource.

- [ ] Add a failing LXC plan test: exactly one unprivileged stopped container, no VM, single firewall-enabled interface on `hsp100`, static `10.77.0.2/30` via `10.77.0.1`, root SSH keys, all firewall resources target container 100 with null `vm_id`, and rules use `net0`.
- [ ] Run `terraform -chdir=modules/vm test -filter=tests/lxc.tftest.hcl -no-color` and confirm failure before implementing.
- [ ] Rename VM template input and add conditional VM/LXC resources, shared guest ID local, endpoint selectors, and `moved { from = proxmox_virtual_environment_vm.this to = proxmox_virtual_environment_vm.this[0] }`. Preserve existing VM argument values and resource addresses for firewalls.
- [ ] Update existing VM test references for `[0]` and `vm_template_id`; assert default VM firewall targeting has null `container_id`. Run leaf tests.

### Task 2: Managed LXC mount volumes and input validation

**Files:** Modify `modules/vm/variables.tf`, `modules/vm/container.tf`, `modules/vm/tests/lxc.tftest.hcl`.

**Interfaces:** `mount_points: list(object({path:string,size_gb:number,datastore_id:optional(string),backup:optional(bool,true)})) = []`. LXC rejects guest `backup = false`; each mount's own backup flag is supported.

- [ ] Add failing tests for two ordered mounts (`/srv/data` 50 GiB on fallback storage, `/srv/cache` 8 GiB on override storage with backup false), and invalid relative/root/dot/duplicate paths, zero/fractional sizes, host-path/full-volume storage values, VM mounts, and LXC backup false.
- [ ] Run the leaf tests and confirm the new assertions fail before adding mount generation/validation.
- [ ] Generate `mount_point` blocks with `volume` set to a validated datastore ID and `size = "${size_gb}G"`; enforce canonical absolute non-root paths, unique paths, positive integer sizes, valid storage IDs including fallback, and only LXC mounts. Keep optional privilege-expanding features disabled.
- [ ] Verify template format/distribution/type validation, root template optionality by guest type, and stopped/autostart constraints with native plans.

### Task 3: Root inventory, wrapper, and cross-type behavior

**Files:** Modify `environments/home/{variables,main,outputs}.tf`, `modules/service_vm/main.tf`, `environments/home/tests/inventory.tftest.hcl`; create `environments/home/tests/lxc.tftest.hcl`.

**Interfaces:** Root `guests` adds `type` and `mount_points` with the leaf defaults. Root globals `vm_template_id` and `lxc_template` pass through the existing service wrapper. `guests` output gains `type`; retains `vm_id`, addresses and DNS names.

- [ ] Add failing mixed inventory tests for VM proxy → LXC backend TCP 8080 and LXC → VM dependency, stable slots, direct/proxy DNS, and inherited global UDP 123 without unintended HTTP/HTTPS. Test a container selected as private proxy and LAN TCP 443 only.
- [ ] Add failing tests for missing LXC template, all-LXC inventory without VM template, invalid type, duplicate cross-type IDs/slots, and service VPN role restrictions across types.
- [ ] Run root tests to establish failures. Propagate the new fields and preserve the existing role/policy/DNS generators. Validate selected template requirements without requiring unused template inputs.
- [ ] Rename template inputs in active tests and run all root/leaf tests.

### Task 4: Compatibility, examples, and deployment documentation

**Files:** Modify `README.md`, `docs/{deployment,firewall-roles}.md`, `environments/home/home.tfvars.example`, ignored `environments/home/home.tfvars`; add a focused legacy-state test fixture or verification script if native tests cannot share legacy state.

- [ ] Capture a controlled legacy VM/firewall state using the pre-change native configuration and mocked providers. Plan with the new configuration; assert moved VM address, no replacement, and no firewall/SDN/DNS recreation. Commit only fixture/check sources, never generated state.
- [ ] Update private tfvars `template_id` → `vm_template_id` preserving its value; add `lxc_template = null` without inventing an installed filename or converting/adding guests.
- [ ] Document global archive configuration, `type = "lxc"`, mount sizing/path/storage/backup, shared 64-slot capacity, root SSH/console bootstrap, stopped activation, unprivileged/shared-kernel boundary, template replacement, mount ordering and data lifecycle, and VM backup/LXC rootfs distinction. Add an illustrative LXC entry to the example only.
- [ ] Ensure Makefile/CI runs the new native tests and compatibility check; keep the pinned provider/runtime requirements consistent.

### Task 5: Final verification and review

- [ ] Run `make check`; inspect every validation/test result and `git diff --check`.
- [ ] Run a mocked plan with the real private inventory to verify all current guests remain VMs, use the renamed template value, retain their policy, and create no containers.
- [ ] Request independent read-only review of the implementation versus the approved spec; fix actionable findings and rerun affected checks.
- [ ] Commit the implementation while leaving the unrelated deployment-doc deletion unstaged. Report the configuration example, verification, and that no live apply ran.

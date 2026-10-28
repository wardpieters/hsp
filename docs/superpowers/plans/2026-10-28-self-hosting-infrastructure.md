# Self-hosting Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build reusable Terraform modules and a guarded operator workflow for isolated Proxmox VMs and automatic Pi-hole DNS.

**Architecture:** Proxmox Simple SDN owns one `/30` per guest; an aggregate router route provides external reachability. Guest and host firewalls enforce access, explicit DNS uses Pi-hole v6, and small managed host files cover persistent routing and the wildcard.

**Tech Stack:** Terraform >= 1.9, pinned bpg/proxmox and lukaspustina/pihole providers, a validated SSH/file provider, Python 3.9+ standard library for operator tooling and host configuration.

**Spec:** `docs/superpowers/specs/2026-10-28-self-hosting-infrastructure-design.md`

## Global Constraints

- No VLAN configuration on the EdgeRouter; one aggregate static route and operator-managed direct guest port forwards.
- Per-guest `/30`, gateway offset 1, VM offset 2; stable explicit slots/VM IDs/VNet IDs.
- Default DROP ingress/egress; explicit dependencies precede protected-range drops, which precede internet/public allowances.
- Pin a guest's source address using `ipfilter-net0`; enforce MAC filtering and IPv6 restrictions.
- Newly created guests remain stopped until a separate activation workflow verifies existing firewall configuration.
- API credentials, state, saved plans, and private variables must not enter Git; TLS and SSH host keys are verified.
- Existing production resources are neither changed nor imported automatically.
- Working VPN/proxy software, native LXC, and live deployment are outside this implementation's initial scope.

## Review Focus

- Aggregate/protected/VPN range overlap and slots on CIDR boundaries must fail before apply (Task 1).
- Rule order must not expose LAN or IPv6 traffic through broad public/update allowances (Task 2).
- A wildcard include migration or failed reload must preserve unrelated DNS and recover the prior configuration (Task 3).
- Saved plans may contain secrets or newly created running guests; tooling must protect plan files and refuse unsafe activation (Task 4).
- Provider mocks cannot prove live packet filtering, reboot persistence, or actual Pi-hole compatibility; docs must distinguish local validation from live acceptance (Task 5).

## File structure

`modules/{platform_network,guest_network,vm,dns_records,service_vm,pihole_host_dns,proxmox_host}` contain focused native-resource modules. `environments/home` composes the normal guest inventory; `environments/host-config` owns the two bounded host boundaries. `scripts/hsp.py` owns guarded Terraform execution, and `scripts/host_config.py` owns host-side validation and configuration activation. Tests live beside Terraform modules and in `tests/` for Python. `docs/deployment.md`, `README.md`, examples, and CI cover use and remaining live checks.

### Task 1: Stable SDN address allocation and inventory validation

**Files:** `modules/platform_network/*.tf`, `modules/guest_network/*.tf`, their `tests/*.tftest.hcl`, root `.gitignore`.

**Interfaces:** `platform_network(platform_cidr, node_name, zone_id, protected_cidrs)` produces zone identity and route CIDR. `guest_network(platform_cidr, slot, zone_id, node_name, vnet_id)` produces `cidr`, `gateway`, `address`, `vnet_id`. Allocate with `cidrsubnet` to prefix 30; no order-based indexing.

- [x] Write mock-provider plan tests asserting slot 3 of `10.77.0.0/24` produces `10.77.0.12/30`, gateway `.13`, guest `.14`, and invalid bounds/overlap fail.
- [x] Run the tests against absent/minimal modules and record the expected failure.
- [x] Implement the validated zone/VNet/subnet resources and documented SDN apply handling.
- [x] Run module validation/tests and commit the deliverable.

### Task 2: Guest firewall and automatic DNS composition

**Files:** `modules/{vm,dns_records,service_vm}/*.tf`, `tests/*.tftest.hcl` in those modules.

**Interfaces:** `vm` accepts explicit identity/template/network settings plus ordered allow rules, protected ranges, approved resolvers/NTP, and update/public profiles. It produces VM ID and policy. `dns_records(records: map({address:string,mode:string,proxy_address:optional(string)}), domain)` produces owned FQDNs. `service_vm` composes Task 1 networking and those modules, exposing guest address and activation metadata.

- [x] Write tests for stopped creation, guest/NIC firewall flags, exact anti-spoofing address, protected-range order, IPv6 blocking, DNS target selection, invalid names, and missing proxy targets; watch expected failures.
- [x] Implement supported native VM, firewall options, IP set, rule, and Pi-hole record resources with stable keys.
- [x] Test only API boundaries with mock providers, while asserting actual derived arguments and policy order; run validation and commit.

### Task 3: Persistent Proxmox routing and Pi-hole wildcard ownership

**Files:** `scripts/host_config.py`, `tests/test_host_config.py`, `modules/{proxmox_host,pihole_host_dns}/*`, `environments/host-config/*`.

**Interfaces:** host helper has explicit `check`, `install`, and `remove` operations for a managed wildcard file/include and aggregate route; filesystem root/command runner are injectable for tests. Terraform manages dedicated desired-config files and invokes the helper on changes; refresh checks surface effective file drift. No full Pi-hole config enters state.

- [ ] Write failing tests using temporary files: preserve unrelated TOML/directives, reject conflicting wildcard owners, rollback on validation/reload failure, remove includes safely, validate private aggregate and prevent injection.
- [ ] Implement bounded idempotent operations, atomic file replacement/backups, host-key-verified SSH/file configuration, reboot persistence, and validated reload triggers.
- [ ] Run all host-helper tests, Terraform validation/mock tests where feasible, and commit.

### Task 4: Guarded Terraform plan/apply/activation

**Files:** `scripts/hsp.py`, `tests/test_hsp.py`.

**Interfaces:** `validate_plan(plan: dict) -> list[str]` returns blocking errors; `verify_activation(plan:dict, api_client) -> None` checks actual Proxmox state for guests changing to started. CLI produces/reviews a saved plan in a private directory and applies only the inspected artifact. API tokens come from environment; no credential is written to command arguments or logs.

- [ ] Write failing fixture tests for create-start, replacement-start, bootstrap/autostart, fail-open interface flags, missing policy/IP sets, unexpected host/API response, and existing unrelated running guests.
- [ ] Implement guards and read-only live activation verification with verified HTTPS, request timeouts, and redacted errors. Require separately provisioned firewall state before starting a guest.
- [ ] Test subprocess boundaries with a fake executable where external Terraform/API calls are unavailable; run the whole Python suite and commit.

### Task 5: Usable home environment, examples, and verification guide

**Files:** `environments/home/*`, `README.md`, `docs/deployment.md`, `Makefile`, `.github/workflows/validate.yml`, example inventories, provider lock files.

**Interfaces:** one map of named guests with explicit VM ID/VNet/slot/role, optional proxy/backend dependencies, and DNS entries. Outputs include route instructions, public forward inventory, guest addresses, and activation status. The environment's lifecycle can be used through Task 4's CLI.

- [ ] Add composition tests for duplicate IDs/slots/names and paired backend ingress/egress, then watch them fail.
- [ ] Implement the environment, role-aware rules, example bootstrap/stopped then activation inventories, and separate host-state configuration.
- [ ] Document exact init/plan/provision/activate/import/recovery commands and which live checks remain unverified.
- [ ] Run `terraform fmt -check -recursive`, every environment/module validation and Terraform test, `python3 -m unittest discover -s tests -v`, and CLI smoke checks. Commit only source/lock/docs.
- [ ] Dispatch one independent whole-branch review; fix important findings with failing regression tests, rerun the full suite, and report remaining live-deployment prerequisites.

## Execution decision

The user explicitly approved the design and instructed implementation. Execute inline in this session without another approval gate. Initialize this new repository and use a feature branch in the supplied empty workspace; no existing checkout needs a second worktree. Keep a durable progress ledger. Do not contact or mutate real Proxmox/Pi-hole systems without supplied deployment configuration.

# LXC mounts and cgroups Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support the user's raw LXC mount and cgroup entries through SSH.

**Architecture:** Forward per-guest inputs to a Terraform SSH resource; its Perl helper edits only exact managed entries under Proxmox's configuration lock. Existing API ownership remains unchanged.

**Tech Stack:** Terraform, built-in terraform_data/remote-exec, host Perl and Proxmox libraries, Node.js test fixtures.

**Spec:** docs/superpowers/specs/2026-10-31-lxc-mounts-cgroups-design.md

## Global Constraints

- Inputs: `lxc_mounts = list(string)`, `lxc_cgroups = map(list(string))`, optional `proxmox_ssh` with host/user/port/host_key.
- No live applies, credentials, automatic restarts, whole-file ownership or unrelated changes.
- Preserve the current feature checkout and unrelated documentation work.

## Review Focus

- Removing inputs must remove prior owned entries.
- Quoting and multiline input must not enable command/config injection.
- Updates must preserve unrelated raw entries and snapshot configuration.
- The SSH host must match the configured Proxmox node.
- Destroy and same-ID container replacement must preserve lifecycle ordering.

## Task 1: SSH configuration and safe editing

- [x] Add failing native plan tests in modules/vm/tests/lxc.tftest.hcl for payloads, defaults, VM rejection, SSH requirements and malformed values.
- [x] Add failing runtime tests in tests/lxc-config.test.mjs for the actual helper's append, idempotence, removal, locked config, and wrong-node behavior.
- [x] Implement modules/vm/lxc_config.tf and modules/vm/scripts/lxc-config.pl; add and forward inputs through environments/home and modules/service_vm.
- [x] Run focused Terraform and Node.js tests; require all cases passing.

## Task 2: Documentation and final checks

- [x] Add the exact user example and SSH/restart/drift guidance to docs/deployment.md; add discoverable example comments and README guidance.
- [x] Add the helper runtime tests to make check without disturbing unrelated Makefile edits.
- [x] Run make check, review the final diff and report limitations.

Verification: `make check` passes 117 native Terraform runs, the existing seven-run REST lifecycle fixture, and eight helper tests. Independent review found one cleanup issue with surrounding whitespace; regression tests reproduce it and the implementation now rejects values that Proxmox would trim. Uppercase cgroup keys are also rejected to match Proxmox's raw-key parser. No additional actionable issues were found. No live SSH or infrastructure apply was performed. Automatic refresh of external raw-entry edits remains outside scope and is documented.

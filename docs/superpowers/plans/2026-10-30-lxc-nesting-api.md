# LXC Nesting API Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage LXC nesting automatically in Terraform with a non-root API token.

**Architecture:** Keep container identity and creation with bpg/proxmox; give a REST resource feature-update ownership, with real API read-back and safe lifecycle ordering.

**Tech Stack:** Terraform >=1.10, bpg/proxmox 0.118.1, magodo/restful 0.25.2, Node.js for local integration fixtures only.

**Spec:** docs/superpowers/specs/2026-10-30-lxc-nesting-api-design.md

## Global Constraints

- Preserve existing resource identities, disks, networking, and per-guest nesting inputs.
- Use a shared sensitive ephemeral API token; honor the existing TLS variable.
- No root credentials, provisioners, live applies, or manual per-container actions.
- Preserve the user's unrelated deployment-doc edit.

## Review Focus

- A nesting disable must send an explicit zero.
- Missing features and explicit false flags must both work without root.
- A replacement using the same CT ID must reapply feature ownership.
- Destruction must never call DELETE on the container through the REST provider.
- Unrelated enabled flags must be rejected before writes.

## Task 1: Native REST feature ownership

**Files:** modules/vm/container.tf, modules/vm/nesting.tf, relevant versions.tf files, environments/home/main.tf and variables.tf, native test files.

- [x] Add failing native tests for nesting payloads, preserved disabled flags, rejected enabled flags, and no REST resources on VMs.
- [x] Add the pinned provider requirements and shared ephemeral authentication input.
- [x] Implement read-back, feature-only PUTs, explicit zero on disable, and replacement ordering.
- [x] Run native tests and verify a copied existing-container plan retains its identity and disks.

## Task 2: API lifecycle verification and documentation

**Files:** tests/nesting-api.mjs, Makefile, docs/deployment.md, README.md if needed.

- [x] Add a local HTTP fixture that exercises the real REST provider and the production module configuration.
- [x] Verify enable/disable, no-op, drift repair, false-flag preservation, rejection, destruction, and replacement.
- [x] Replace manual workaround guidance with automatic Terraform behavior and credential migration.
- [x] Run make check, review, and commit only task changes.

Verification: `make check` passes 104 native runs plus seven API integration runs. Independent review found no actionable issues. The ignored local `.env` token key was renamed without changing its value. A real-provider regression exposed a read-template error when the entire features property is removed externally; projecting `data|{features}` fixes it and the additional regression passes. Existing-volume adoption was checked against copied Plex state with localhost-only API endpoints and refresh disabled.

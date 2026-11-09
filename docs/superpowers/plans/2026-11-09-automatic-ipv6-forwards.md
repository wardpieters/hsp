# Automatic IPv6 Forwarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Derive public TCP/UDP forwarding and all-managed-guest hairpin from guest public ports.

**Architecture:** Home resolves protocol/port ownership and generates source-to-forward grants. Existing ingress, service and VM modules carry protocol through firewall rendering and connection revocation.

**Tech Stack:** Terraform HCL, nftables, POSIX shell/awk, Node test runner.

**Spec:** `docs/superpowers/specs/2026-11-09-automatic-ipv6-forwards-design.md`

## Global Constraints

- Unique guest owner per protocol/port; repeated declarations by that owner deduplicate.
- All managed guests can hairpin when any forward exists, including self-hairpin and guests without internet egress.
- Preserve gateway SNAT, exact VNet/address matching, management-port restrictions and bridge zones.
- HE disabled creates no IPv6 entries; no live infrastructure applies.
- Preserve existing TCP permission manifests and replay outstanding pre-upgrade cleanup journals as TCP.

## Review Focus

- TCP/UDP same-number forwards must remain independent during cleanup.
- A hairpin source without public ports or egress must still receive IPv6 networking.
- UDP source port zero is valid and must survive tuple parsing; destination public ports remain 1..65535.
- Pending cleanup must remain retryable across failures and software upgrades.
- Removing the final public port must retain networking needed for independent egress.

### Task 1: Carry protocol through ingress, guest firewalls and cleanup

**Files:** `modules/ipv6_ingress/{variables,main}.tf`, its two ingress templates and tests; `modules/vm/ipv6.tf`, VM IPv6/hairpin tests; `modules/service_vm/main.tf`; `tests/ipv6-ingress.test.mjs` and test helpers as needed.

**Interfaces:** Add `protocol = optional(string, "tcp")` to ingress `forwards` and `hairpin` entries and VM/service hairpin grants. Change VM/service `ipv6_forwarded_ports` to `list(object({ protocol = string, port = number }))`. Forward keys remain caller-supplied inside the ingress module. Permission records retain D/P field order and carry TCP or UDP in the existing protocol field.

- [x] Add failing Terraform tests for UDP NAT, protocol-specific native firewall exceptions, same-number TCP/UDP forwards and invalid protocols. Update numeric forwarded-port test inputs to protocol/port objects.
- [x] Add failing Node helper tests for UDP cross-guest/self flows, protocol-isolated revocation/remapping, egress revocation preserving hairpin, zero source ports, malformed tuple failure and retryable cleanup. Keep existing TCP regression tests.
- [x] Run affected Terraform tests and `node --test tests/ipv6-ingress.test.mjs`; confirm failures expose missing UDP behavior.
- [x] Render protocols and connection protocol numbers consistently through DNAT/SNAT, related errors, original/reply guards and native rules. Validate ownership by protocol/port.
- [x] Generalize helper enumeration, parsing, purge and journal replay to TCP/UDP. Add protocol to new journal rows; accept old rows as TCP. Keep exact translated source-port cleanup and fail-closed retries.
- [x] Run affected Terraform and Node tests; require all to pass before proceeding.

### Task 2: Derive forwarding and all-guest hairpin in home

**Files:** `environments/home/{ipv6,main,outputs}.tf`, `environments/host-config/ipv6.tf`, root IPv6/hairpin tests, `environments/he-ipv6.tfvars` and `.example`.

**Interfaces:** Home groups distinct guest declarations by `${protocol}-${port}`, rejects groups with multiple guest owners using blocking validation, and resolves one forward per valid owner. Generate `source_guest/forward_key` hairpin entries for every guest and forward. Outputs preserve existing fields and expose the actual protocol; forward keys become generated keys.

- [x] Add failing root tests for derived TCP/UDP forwards, same-number different protocols, duplicate same-owner declarations, conflicting owners, all-guest/self hairpin, no-egress sources and participant slot overflow.
- [x] Replace obsolete manual-map test scenarios with guest inventory changes. Cover HE disabled, empty public ports and retained egress after final public-port removal.
- [x] Run root tests and confirm the new derivation assertions fail against current behavior.
- [x] Remove the two manual input fields and validations in both roots. Derive protocol-aware forwards/grants, participants, native module inputs and outputs. Ensure conflicts report a useful blocking diagnostic rather than an eager duplicate-map-key failure.
- [x] Remove manual fields from the actual ignored tfvars and tracked example without changing other tunnel settings. Host-config continues to consume tunnel settings only.
- [x] Run both roots' tests and validation; require all to pass.

### Task 3: Document and verify the integrated change

**Files:** `docs/ipv6.md`, other active operator documentation mentioning manual HE maps, and this plan.

**Interfaces:** Document `public_ports` as the sole source for public IPv6 forwarding and managed-guest hairpin; generated output keys and conflict diagnostics are operator-visible changes.

- [x] Replace manual configuration examples and explicit-client-grant guidance with automatic TCP/UDP behavior. Update live acceptance to exercise both protocols and same-number isolation; retain the offline/live distinction.
- [x] Run `make check`, including Terraform formatting, validation, all Terraform tests and all four Node suites. If dependencies/tools are absent, use available bundled/cached executables or report the precise blocker.
- [x] Review the complete diff against the approved spec, checking legacy TCP manifests/journals, UDP port-zero parsing and failure recovery. Fix findings and rerun affected checks.
- [x] Mark completed steps and report verification evidence and any remaining limits. Preserve pre-existing lockfile changes and `environments.zip`; do not deploy or merge.

## Completion evidence

Implemented in the existing `codex/ipv6-hairpin` checkout. `make check` passed:
10 configurations validated, 283 Terraform tests and 51 Node tests. Website
document tests passed (3 tests); `git diff --check` and shell syntax checks
passed. Independent whole-change review reported no findings. No live apply
or Linux packet acceptance was performed. Existing lockfile changes and the
untracked environments archive were preserved.


## Follow-up correction: source permissions (2026-11-09)

The user clarified that hairpin must require matching effective internet
egress OR an explicit directed guest-to-guest connection. This supersedes
the original all-guest grant requirements above.

- [x] Reproduce TCP 587 incorrectly permitting VIP TCP 80 with a failing test.
- [x] Derive authorized forward keys from effective source egress or exact
  explicit source/target/protocol/port connections before address resolution.
- [x] Restrict IPv6 participants to public targets, effective-egress guests
  and authorized hairpin sources, keeping bridge identities consistent.
- [x] Cover TCP/UDP isolation, self access, directional/target matching,
  external-address exclusion, inherited egress and connection-only LXC access.
- [x] Update the operator guide and example to describe the corrected policy.
- [x] Run full repository checks and independent review of the correction.

Correction verification: `make check` passed all 287 Terraform tests and
51 Node tests across ten validated configurations. All three website tests,
formatting and diff checks passed. Independent review reported no findings.

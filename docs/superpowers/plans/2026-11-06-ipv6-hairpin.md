# Managed-guest IPv6 Hairpin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let explicitly granted managed VMs/LXCs reach selected existing public IPv6 TCP forwards, including their own service.

**Architecture:** Home resolves guest-to-forward grants into exact NAT tuples and native guest firewall exceptions. Extend the existing IPv6 ingress owner with routed DNAT and target-gateway SNAT, preserving separate bridge/routed conntrack zones. Extend its manifest and retryable cleanup to revoke individual grants without resetting unrelated flows.

**Tech Stack:** Terraform/HCL, existing pinned Proxmox/system providers, nftables, conntrack-tools, POSIX shell/awk, Node.js test fixtures, Docusaurus.

**Spec:** [Approved managed-guest hairpin design](../specs/2026-11-06-ipv6-hairpin-design.md). Read both documents before execution.

**Status:** Tasks 1–5 implemented and offline verified. Task 4 final `make check` passed (296 Terraform tests, 36 Node tests); documentation release checks pass. Linux live acceptance remains pending. Baseline `c364523` includes the bridge-zone corrections. Do not deploy intermediate task commits.

## Global Constraints

- Managed guests only; hairpin grants default to `{}` and name existing TCP forwards.
- Use gateway SNAT for both cross-guest and self-hairpin; external HE ingress preserves client identity.
- Keep Terraform >=1.10 and <2.0 in home; >=1.9 and <2.0 in modules and host-config.
- Keep bpg/proxmox 0.118.1, neuspaces/system 0.5.0, lukaspustina/pihole 0.3.1 and magodo/restful 0.25.2.
- Keep the established pve-firewall backend, exact bridge zone 1 and routed NAT zone 0.
- Preserve IPv4 resources, internet-egress inheritance, existing output shapes and IPv4-only local DNS.
- Preserve all pre-existing checkout changes and private tfvars; stage only this feature's own changes.
- No global ruleset/conntrack flush, new host dependencies, automatic network/guest restart, live apply or router/DNS change.

## Review Focus

1. Revoking internet TCP 443 must retain an independent hairpin grant on TCP 443, and vice versa (Task 3).
2. Two clients sharing a TCP source port, plus a self-hairpin client, must retain distinct translated flows and selective cleanup (Tasks 2–3; live checks in Task 5).
3. A VM/LXC with no incoming service or internet permission must gain IPv6 solely for its grant and lose it when its final participation reason disappears (Task 4).
4. Generic DNAT/state accepts must not admit ungranted guest traffic or change external client identity (Tasks 1–2; live checks in Task 5).
5. Cleanup failure after deleting zone 0 must remain retryable using persisted translated-port snapshots, including service stop and bridge changes (Task 3).

## File map and execution order

| Files | Responsibility |
| --- | --- |
| `modules/vm/ipv6.tf`, `modules/service_vm/main.tf` | New native firewall inputs, validation, ordered exceptions and pass-through |
| `modules/ipv6_ingress/variables.tf`, `main.tf`, `templates/ingress.nft.tftpl` | Resolved grant validation, manifest rendering, NAT and forwarding guard |
| `modules/ipv6_ingress/templates/ingress.sh.tftpl` | Grant revocation, tuple snapshots, bridge migration and retry |
| `tests/helpers/network-fixture.mjs`, `tests/ipv6-ingress.test.mjs` | Mocked tuple enumeration and lifecycle evidence |
| `environments/home/ipv6.tf`, `main.tf`, `outputs.tf` | Public configuration, participant union, resolution and output |
| `environments/host-config/ipv6.tf` | Shared configuration schema and validation only |
| New `hairpin.tftest.hcl` files under the two roots, `modules/vm/tests` and `modules/ipv6_ingress/tests` | Focused policy, NAT and integration tests |
| `docs/ipv6.md`, `docs/firewall-roles.md`, `docs/verification.md`, `environments/he-ipv6.tfvars.example` | Operator contract, examples and live acceptance |

Execute Tasks 1–5 in order. At execution time inspect status and use the worktree skill before implementation; retain the approved spec and plan in the execution checkout. Tests use mock providers and teardown overrides, never a live Proxmox endpoint. Existing `make check` discovers new Terraform test files; do not create another runner or modify provider pins.

## Task 1: Native guest firewall exceptions

**Files:** Modify `modules/vm/ipv6.tf`, `modules/service_vm/main.tf`; create `modules/vm/tests/hairpin.tftest.hcl`.

**Interfaces:** Consume `network.ipv6`, `ipv6_forwarded_ports` and protected ranges. Produce `ipv6_hairpin_out: list(object({ public_address = string, port = number }))` and `ipv6_hairpin_in: list(object({ gateway = string, port = number }))`, both default `[]`, on `vm` and `service_vm`. Preserve `output.rules`.

- [x] **Step 1: Add failing policy tests.** Reuse mocks/guest inputs from `modules/vm/tests/ipv6.tftest.hcl`. Use VIP `2001:470:1f15:4d6::2`, guest `fd42:77:1:2::2`, gateway `fd42:77:1:2::1`, port 443. Name runs `hairpin_vm`, `hairpin_lxc`, `reject_hairpin_without_network`, `reject_wrong_gateway`, `reject_unforwarded_incoming_port`, `reject_non_global_vip`, `reject_invalid_port`, and `empty_hairpin_preserves_policy`. Assert outgoing exact VIP/128 TCP443 and incoming gateway/128 to guest/128 TCP443 precede protected drops. Use stable comments `hsp:ipv6:hairpin-out:443` and `hsp:ipv6:hairpin-in:443`:

```hcl
index([for r in output.rules : r.comment], "hsp:ipv6:hairpin-out:443") < index([for r in output.rules : r.comment], "hsp:ipv6:protect-out:2001:470:1f15:4d6::/64")
length([for r in output.rules : r if r.comment == "hsp:ipv6:hairpin-in:443" && r.source == "fd42:77:1:2::1/128" && r.dest == "fd42:77:1:2::2/128" && r.proto == "tcp" && r.dport == "443"]) == 1
```

Also assert duplicated input grants generate one rule, no wildcard TCP allowance, exact anti-spoofing source entries remain, and both defaults produce the baseline rules.

- [x] **Step 2: Run the new suite red.** Run `terraform -chdir=modules/vm test -filter=tests/hairpin.tftest.hcl -no-color`; expect missing input/exception assertions to fail.
- [x] **Step 3: Implement the two inputs and ordered rules in `modules/vm/ipv6.tf`.** Outgoing VIPs must be canonical global /128 host strings; incoming gateway must equal `network.ipv6.gateway`, and its port must appear in `ipv6_forwarded_ports`. Require integer ports 1..65535 and IPv6 networking for nonempty lists. Keep control-denial ordering, deduplicate and insert application exceptions immediately before protected drops.
- [x] **Step 4: Pass the inputs through `modules/service_vm/main.tf`.** Add the same types/defaults and named arguments to `module.vm`; do not change the guest inventory object or DNS module.
- [x] **Step 5: Verify green.** Run the new suite and `terraform -chdir=modules/vm test -filter=tests/ipv6.tftest.hcl -no-color`; both must pass. Run `terraform -chdir=modules/service_vm validate -no-color`; expect success.
- [x] **Step 6: Commit only Task 1 files.** Suggested message: `feat(ipv6): add scoped guest hairpin firewall exceptions`.

## Task 2: Resolved hairpin NAT and forwarding guard

**Files:** Modify `modules/ipv6_ingress/variables.tf`, `main.tf`, `templates/ingress.nft.tftpl`; create `modules/ipv6_ingress/tests/hairpin.tftest.hcl`.

**Interfaces:** Produce module input `hairpin`, default `{}`, with the exact nine-field object type from the spec's Internal module interface. Keys are `source_guest/forward_key`. Render sorted `P|VIP|SOURCE|tcp|PORT|SOURCE_VNET|TARGET|TARGET_VNET|GATEWAY` records after the existing topology header; retain D/E formats. Pass `hairpin = var.hairpin` into the nft template. Task 3 adds cleanup before these entries are wired into home.

- [x] **Step 1: Add failing module tests.** Mock `system` and override `module.teardown` as in `tests/ingress.tftest.hcl`. Use forward `https` to proxy at `fd42:77:1:2::2`/`hsp1002`, source cloud at `fd42:77:1:1::2`/`hsp1001`, and proxy self-hairpin. Name runs `cross_and_self_hairpin`, `empty_hairpin`, `reject_unknown_forward`, `reject_mismatched_target`, `reject_wrong_gateway`, `reject_invalid_source`, `reject_mismatched_composite_key`, `hairpin_only_source_bridge`, `he_accepts_are_path_scoped`, and `hairpin_errors_precede_protected_denials`. Assert these exact manifest rows exist once:

```text
P|2001:470:1f15:4d6::2|fd42:77:1:1::2|tcp|443|hsp1001|fd42:77:1:2::2|hsp1002|fd42:77:1:2::1
P|2001:470:1f15:4d6::2|fd42:77:1:2::2|tcp|443|hsp1002|fd42:77:1:2::2|hsp1002|fd42:77:1:2::1
```

Assert routed DNAT includes exact source interface/address/VIP/port; SNAT includes DNAT ownership, original source/VIP/port, target interface/address and gateway. Assert both forward directions use current tuples and routed interfaces; the first request does not require SNAT status before postrouting. External public accepts must require HE original/reply paths. Related-error accepts precede protected drops without requiring a router source to equal the application endpoint. No hairpin OUTPUT NAT, wildcard NAT, or fixed source-port rewrite is generated; unchanged bridge tracking remains exact and before conntrack.

- [x] **Step 2: Run the new suite red.** Run `terraform -chdir=modules/ipv6_ingress test -filter=tests/hairpin.tftest.hcl -no-color`; expect missing input/rules/manifest assertions to fail.
- [x] **Step 3: Implement the resolved input, validation and rendering.** Validate names/VNets, exact canonical ULA hosts, target gateway offset 1, matching `forwards[forward_key]`, composite key consistency, and no contradictory duplicate source/VNet identities. Include source and target addresses in the allowed `firewall_bridges` participant set. Preserve the existing service/table owners and revision-trigger behavior.
- [x] **Step 4: Implement the exact routed NAT and guarded request/reply/error paths.** Retain zone-1 intermediate traversal handling and zone-0 NAT. Narrow baseline external DNAT acceptance so P grants cannot inherit it; keep normal internet SNAT limited to `hsp-he6`. Let NAT allocate translated source ports.
- [x] **Step 5: Verify green and baseline rendering.** Run `terraform -chdir=modules/ipv6_ingress test -no-color`; expect all ingress, bridge-zone and hairpin assertions to pass. These are rendering checks, not evidence of working Linux packet traversal.
- [x] **Step 6: Commit only Task 2 files.** Suggested message: `feat(ipv6): render granted gateway-SNAT hairpin paths`.

## Task 3: Selective conntrack cleanup with durable retry snapshots

**Files:** Modify `modules/ipv6_ingress/templates/ingress.sh.tftpl`, `tests/helpers/network-fixture.mjs`, `tests/ipv6-ingress.test.mjs`; extend `modules/ipv6_ingress/tests/hairpin.tftest.hcl` with applied fixtures named `enabled`, `grant_revoked`, `egress_revoked`, `remapped`, and `self_only`.

**Interfaces:** Consume Task 2 P records and rendered `rules.nft`, `permissions`, `bridge-zones`. Preserve shell entrypoints `start|reload|stop`, existing D/E manifests and teardown command. Extend fixture flows with `replySrc`, `origSport`, `replyDport`, keeping existing `origSrc`, `origDst`, `replyDst`, `proto`, `port`, `zone`. Fake `conntrack -L -f ipv6 --zone 0 ... -o extended` emits real-format original/reply tuple fields; fake deletion supports `--reply-src` and `--sport` in addition to existing selectors.

- [x] **Step 1: Add failing lifecycle tests using rendered Task 2 fixtures.** Name tests `hairpin revocation preserves independent flows`, `egress revocation preserves same-port hairpin`, `translated source-port collisions clean up selectively`, `self-hairpin stop is idempotent`, `cleanup resumes after zone-zero deletion`, `malformed enumeration blocks reductions`, `bridge changes revoke source and target views`, `old manifests adopt hairpin without broad purges`, and `failed hairpin reduction retains guard`. Use two source guests sharing original source port 50000, translated ports 50000 and 50001, target gateway/guest from Task 2, plus external ingress and ordinary internet flows. For removal of cloud's grant assert remaining IDs exactly:

```js
assert.deepEqual((await f.read()).flows.map(x => x.id).sort(), [
  'external', 'internet', 'other-client-bridge', 'other-client-routed',
  'other-client-source', 'self-bridge', 'self-routed', 'self-source',
].sort());
```

Assert no-op/additions preserve all existing flows. Inject failure on a target-zone deletion after zone 0 was deleted; retry must still delete the target entry from a saved snapshot. Test `-L` failure, malformed/partial tuple output and successful empty enumeration separately. Assert retryable stop after inactive service, no global flush, guard installation before destructive cleanup, and unrelated guests/tables unchanged. E-revocation tests must include both retained P and retained UDP/ICMP permissions; P-revocation must preserve independent E443.

- [x] **Step 2: Run the new tests red.** Run `node --test tests/ipv6-ingress.test.mjs`; expect new cleanup assertions to fail while existing fixtures still run without live networking.
- [x] **Step 3: Extend the fixture's tuple model.** Implement filtered listing/deletion using the fields above and real two-direction output order. Inspect generated commands as well as final state; never copy the production selection algorithm into fixture matching.
- [x] **Step 4: Extend helper parsing and reduction ownership.** Recognize exact nine-field P rows in preflight, old/new union, reduction detection, stop and bridge migration. Preserve topology H and legacy D/E records. Preflight both source/target VNets. Check old and new bridge profiles for either endpoint; a hairpin-only source must be covered even without an E record.
- [x] **Step 5: Implement persisted per-connection cleanup.** Under the blocking/narrowed guard enumerate affected zone-0 tuples with original source/VIP/TCP/port selectors and validate complete original/reply address/port fields. Atomically persist original and translated source ports and endpoint addresses in `$runtime/hairpin-pending` before deleting any tuple. Delete exact target zone-1 `GATEWAY:translated_port -> TARGET:PORT`, source-side zone-1 `SOURCE -> VIP:PORT`, and affected zone-0 tuples. Replay a pending journal before taking a new snapshot; remove it only after all recorded deletions succeed. Any parse/list/delete error retains the guard and recovery metadata. Empty lists are valid.
- [x] **Step 6: Narrow overlapping E cleanup and coordinate D/remap cleanup.** Reuse exact enumerated original tuples for zone-1 egress cleanup instead of a broad source/protocol/port purge that catches P flows. Snapshot affected P flows before any D purge can delete their zone-0 evidence. Preserve unchanged grants, including another client to the same target/port. Include pending snapshots in stop/retry; do not change explicit SSH teardown semantics.
- [x] **Step 7: Verify green.** Run `node --test tests/ipv6-ingress.test.mjs` and `terraform -chdir=modules/ipv6_ingress test -no-color`; expect all lifecycle and rendering tests to pass. Confirm fake-only command execution and no `conntrack -F`/global ruleset flush in logs.
- [x] **Step 8: Commit only Task 3 files.** Suggested message: `fix(ipv6): revoke hairpin conntrack tuples with retry journals`.

## Task 4: Root configuration, hairpin-only guests and outputs

**Files:** Modify `environments/home/ipv6.tf`, `main.tf`, `outputs.tf`, `environments/host-config/ipv6.tf`; create `environments/home/tests/hairpin.tftest.hcl`, `environments/host-config/tests/hairpin.tftest.hcl`.

**Interfaces:** Consume Tasks 1–3 inputs. Produce shared `he_ipv6.hairpin = optional(map(set(string)), {})`, local `he_ipv6_hairpin` with Task 2's exact object shape, and home output `ipv6_hairpin` with the exact field set from the spec. Existing outputs and both roots' default-off behavior remain compatible.

- [x] **Step 1: Add failing root tests.** Reuse existing mocks and override `module.ipv6_ingress[0].module.teardown`. Use cloud/proxy at slots 1/2 with the Task 2 addresses, no global or guest internet egress, and `hairpin = { cloud = ["https"], proxy-public = ["https"] }`. Name runs `hairpin_only_vm`, `hairpin_only_lxc`, `self_hairpin`, `reject_unknown_source`, `reject_unknown_forward`, `reject_empty_set`, `reject_bad_names`, `allow_unreferenced_legacy_forward_key`, `off_tolerates_saved_references`, `remove_last_grant`, `retain_other_participation`, `restrictive_role_requires_explicit_grant`, and `host_config_has_no_hairpin_resources`. Core assertions:

```hcl
output.ipv6_networks["cloud"].address == "fd42:77:1:1::2" && length(output.ipv6_egress) == 0
output.ipv6_hairpin["cloud/https"].translated_source_address == "fd42:77:1:2::1"
output.ipv6_hairpin["cloud/https"].public_address == "2001:470:1f15:4d6::2" && output.ipv6_hairpin["cloud/https"].protocol == "tcp"
```

Assert exact output key sets, no source public listener/internet rule, both owned bridges present, duplicate set entries deduplicated, and host firewall ownership both true/false adds no hairpin host acceptance. Removal of cloud's final grant removes only cloud's ULA while preserving its IPv4 identity; keeping E or D participation retains its ULA. An off run yields empty hairpin/IPv6 outputs and no ingress instance. Host-config tests compare its existing desired resource content with/without hairpin under the same HE settings.

- [x] **Step 2: Run root tests red.** Run `terraform -chdir=environments/home test -filter=tests/hairpin.tftest.hcl -no-color` and `terraform -chdir=environments/host-config test -filter=tests/hairpin.tftest.hcl -no-color`; expect missing output/schema behavior to fail.
- [x] **Step 3: Add the shared field and enabled-only validation to both roots.** Enforce the spec's exact source and referenced-forward regexes, nonempty sets and referenced forward existence. Home validates source inventory and participant slots. Avoid eager missing-key indexing so invalid inputs produce validation errors; allow well-typed saved references while off. Do not impose new grammar on unreferenced existing forward keys.
- [x] **Step 4: Resolve and wire home grants.** Union hairpin sources into `he_ipv6_participants`; resolve source/target networks and target gateway into `he_ipv6_hairpin`. Pass deduplicated per-guest outbound/inbound Task 1 lists through `module.service`, and Task 2 entries into `module.ipv6_ingress`. Include all participants in bridge mapping. Preserve effective internet inheritance and instantiate ingress for any D/E/P permission.
- [x] **Step 5: Add output `ipv6_hairpin`.** Use composite keys, all spec fields, TCP protocol and gateway `translated_source_address`; empty map when off/unconfigured. Do not change existing output schemas or host-config networking resources.
- [x] **Step 6: Verify green and integration.** Run both roots' new suites, then `make check`; expect all formatting, validation, Terraform mock tests and Node suites to pass. No SSH/apply against the real environment. If an unrelated baseline failure appears, record it and distinguish it from feature failures before proceeding.
- [x] **Step 7: Commit only Task 4 files.** Suggested message: `feat(ipv6): resolve explicit managed-guest hairpin grants`.

## Task 5: Operator documentation and release verification

**Files:** Modify `docs/ipv6.md`, `docs/firewall-roles.md`, `docs/verification.md`, `environments/he-ipv6.tfvars.example`. The design/plan navigation entries are already added by the planning deliverable; retain them.

**Interfaces:** Consume the public shared-field/output contracts from Task 4. Produce operating instructions that distinguish implemented offline behavior from separate live acceptance.

- [x] **Step 1: Update examples and scope.** Keep the shared example globally disabled with `hairpin = {}` by default; show opt-in guest-to-forward grants separately. Replace the current blanket hairpin exclusion with managed-only support and continued LAN/VPN-prefix exclusion. Explain gateway identity, independent E/P grants, hairpin-only IPv6 participation, explicit role exceptions, self-hairpin, application listeners and IPv4-only local DNS.
- [x] **Step 2: Document rollout, removal and recovery.** Pass the same file to both roots; adding grants changes home while host-config should have no networking delta. Retain stopped-first provisioning/OS ULA checks. Revoke through home with SSH retained, describe pending-journal retry and guard retention, and preserve the baseline whole-feature disable order. Describe `ipv6_hairpin` as desired state, not health.
- [x] **Step 3: Add an operator acceptance matrix.** Cover VM-to-LXC, LXC-to-VM, self-hairpin, concurrent fixed-source-port clients, gateway identity, VIP reply identity, large transfers and related ICMPv6, exact zone-0 and both zone-1 views, and no application packets on `hsp-he6`. Include negative tests for ungranted clients/ports, direct ULA, spoofing, LAN access and management. Include active E/P revocation, unrelated sessions, service/firewall reload and reboot, external client-source preservation, and baseline TCP/UDP/ICMP egress. List `nft -c`, compiled Proxmox rules, `conntrack -L -f ipv6 -o extended` and packet captures as evidence. These checks are documented for the operator; do not run them against live infrastructure during execution.
- [x] **Step 4: Run release verification.** After code tasks run `make check`, `npm --prefix website test`, `make docs-build`, and `git diff --check`; require exit 0 for each. Task 5 reuses Task 4's final unchanged-runtime `make check` evidence (296 Terraform tests and 36 Node tests), as authorized for this documentation-only task; website tests/build and whitespace checks were run for the documentation changes. Review the final diff against every spec section, including unchanged IPv4/provider/DNS ownership. Record that Linux live acceptance remains pending; mocks and a documentation build cannot prove hairpin traffic works.
- [x] **Step 5: Commit only Task 5 files.** Suggested message: `docs(ipv6): explain managed-guest hairpin and acceptance`.

## Coverage and handoff

Configuration, identities, defaults and lifecycle are covered by Tasks 1/4;
packet authorization and translation by Task 2; revocation, migration,
compatibility and failures by Task 3; operator boundaries and live evidence
by Task 5. Review Focus items are assigned to tests above. Types, manifest
fields and output names match the approved spec. Implementation and offline tests are complete. No Linux live acceptance is
claimed; the operator matrix remains pending.

Recommended execution: **subagent-driven**, because cleanup must coordinate
two conntrack zones, translated source ports and independent E/P permissions;
a missed interaction could leave stale access or reset another guest's
sessions. Review the plan and choose an execution method before starting
implementation, as required by the writing-plans workflow.

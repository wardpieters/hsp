# Implementation verification

This repository contains Terraform configuration and native Terraform tests. These checks do not deploy Proxmox, Pi-hole or EdgeRouter configuration; operator-run deployments are separate.

The 2026-10-29 scope corrections removed the custom deployment wrapper, host helpers, and Pi-hole wildcard file/service module. Host routing uses Terraform-managed Proxmox systemd files/services. DNS uses explicit local records through the Pi-hole API and the `dns_records` module, with no Pi-hole SSH access. New guests default to stopped, with inspection and first start performed in separate ordinary Terraform applies.

Run `make init` and `make check` to initialize the pinned providers, check formatting, validate every configuration, run mock-provider tests, and exercise the real REST provider against a loopback-only API fixture. These checks do not connect to live infrastructure. Node.js >=22 is required for the API fixture.

Verified on 2026-10-29 with Terraform 1.14.8: all eight configurations validate, all 32 Terraform tests pass, recursive formatting passes, and Git whitespace checks pass. No project source files require Python.

Verified on 2026-10-30 with Terraform 1.14.8 and Node.js 24: all eight configurations validate and all 104 native Terraform test runs pass. The API fixture adds seven real-REST-provider Terraform runs for enabling, disabling, unchanged plans, external drift, removed feature fields, preservation of explicit zeros, and container replacement. Its request assertions also verify feature-only PUTs and safe cleanup without DELETE. A copied Plex-state plan with refresh disabled preserves CT 1009 and its existing mount volumes while adding REST feature ownership. No live apply was run.

The tests exercise address bounds/overlaps, stable slots, DNS targets, firewall ordering, inventory/role restrictions, SDN repair/apply lifecycles, and host-file repair/service triggers. Provider mocks cannot prove real packet filtering, systemd command execution, Pi-hole behavior, or reboot persistence. Those checks remain in the [deployment guide](deployment.md).

The host startup regression also checks that the `pve-guests` drop-in uses startup checks without a `Requires` relationship. That relationship could propagate an explicit routing stop into Proxmox's node-wide guest shutdown action. This is a configuration regression test, not a live systemd execution test.

## Optional HE IPv6 (2026-11-06)

HE is default-off and is verified offline with pinned providers. Mock-provider tests cover shared configuration and address-family validation, ULA allocation, SDN repair/removal, VM/LXC initialization, ordered guest/host control policy, effective global/per-guest/role TCP/UDP/ICMP egress, outputs and toggle transitions. Node subprocess tests execute the actual Terraform-rendered helpers against isolated fake ip/nft/sysctl/conntrack tools, exercising ownership collisions, partial failure, selective NAT revocation, retained flows and failure guards. A PMTU regression checks related errors precede protected-source drops. Final-review regressions exercise the rendered teardown commands after a failed stop leaves systemd inactive, rejected permission reductions with established flows, and safe failed additions. The teardown tests simulate systemd and run the exact command stored in the Terraform resource; they do not execute a live SSH destroy.

The offline run passed `make check` (ten validated configurations, 244 native Terraform test runs and 23 Node tests), `make docs-build`, and `git diff --check`. No real host network commands are used by the helper tests. These checks do not prove Linux nft syntax, legacy bridge/conntrack packet paths, live HE transport, public DNS, mail delivery or reboot persistence. Those remain the operator's [IPv6 live acceptance checks](ipv6.md#live-acceptance). No live apply, router/old-endpoint operation, public DNS change or guest restart was performed by this implementation.

## Native-rule IPv6 corrections (2026-11-06)

The operator supplied a live capture showing ULA-sourced echo requests
leaving `hsp-he6` without SNAT. The correction separates exact owned legacy
firewall bridges into zone 1, retaining zone 0 for routing/NAT. Regressions
cover migration of broken untranslated bindings, targeted two-zone cleanup,
retained no-op/foreign sessions, failure guards and adding a guest without
resetting existing guests. Root tests derive bridges from VM IDs even when
VNet names differ.

The portless outbound ICMP protocol uses canonical `ipv6-icmp`; typed
native rules retain legacy encoding and its known editor warning at the
operator's request. No new Perl policy files or security groups remain.
The local reproduction VM was stopped at the user's request before any
packet test and removed. No local VM/container or live apply is used for
verification. A subsequent operator capture confirmed echo requests leaving
`hsp-he6` with the public VIP as their source. The operator later confirmed
IPv6 HTTP egress; successful external ingress remains unverified.

The final native-only verification passed `make check`: ten configurations,
247 native Terraform test runs and 26 Node tests. `make docs-build` and
`git diff --check` also pass. The rejected policy-helper implementation and
its tests are absent from this result.

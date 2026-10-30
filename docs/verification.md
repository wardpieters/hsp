# Implementation verification

This repository contains Terraform configuration and native Terraform tests. No Proxmox, Pi-hole, or EdgeRouter deployment has been performed.

The 2026-10-29 scope corrections removed the custom deployment wrapper, host helpers, and Pi-hole wildcard file/service module. Host routing uses Terraform-managed Proxmox systemd files/services. DNS uses explicit local records through the Pi-hole API and the `dns_records` module, with no Pi-hole SSH access. New guests default to stopped, with inspection and first start performed in separate ordinary Terraform applies.

Run `make init` and `make check` to initialize the pinned providers, check formatting, validate every configuration, run mock-provider tests, and exercise the real REST provider against a loopback-only API fixture. These checks do not connect to live infrastructure. Node.js >=22 is required for the API fixture.

Verified on 2026-10-29 with Terraform 1.14.8: all eight configurations validate, all 32 Terraform tests pass, recursive formatting passes, and Git whitespace checks pass. No project source files require Python.

Verified on 2026-10-30 with Terraform 1.14.8 and Node.js 24: all eight configurations validate and all 104 native Terraform test runs pass. The API fixture adds seven real-REST-provider Terraform runs for enabling, disabling, unchanged plans, external drift, removed feature fields, preservation of explicit zeros, and container replacement. Its request assertions also verify feature-only PUTs and safe cleanup without DELETE. A copied Plex-state plan with refresh disabled preserves CT 1009 and its existing mount volumes while adding REST feature ownership. No live apply was run.

The tests exercise address bounds/overlaps, stable slots, DNS targets, firewall ordering, inventory/role restrictions, SDN repair/apply lifecycles, and host-file repair/service triggers. Provider mocks cannot prove real packet filtering, systemd command execution, Pi-hole behavior, or reboot persistence. Those checks remain in the [deployment guide](deployment.md).

The host startup regression also checks that the `pve-guests` drop-in uses startup checks without a `Requires` relationship. That relationship could propagate an explicit routing stop into Proxmox's node-wide guest shutdown action. This is a configuration regression test, not a live systemd execution test.

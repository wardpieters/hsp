# Implementation verification

This repository contains Terraform configuration and native Terraform tests. No Proxmox, Pi-hole, or EdgeRouter deployment has been performed.

The 2026-10-29 scope correction removed the custom deployment wrapper, host helpers, and their interpreter requirement. Host routing now uses Terraform-managed systemd files/services; wildcard targets use a dedicated file plus the existing FTL service. Registering that file in Pi-hole and adopting the previous wildcard are documented one-time operations. New guests default to stopped, with inspection and first start performed in separate ordinary Terraform applies.

Run `make init` and `make check` to initialize the pinned providers, check formatting, validate every configuration, and run mock-provider tests. These checks do not connect to live infrastructure.

Verified on 2026-10-29 with Terraform 1.14.8: all nine configurations validate, all 36 Terraform tests pass, recursive formatting passes, and Git whitespace checks pass. No project source files require Python.

The tests exercise address bounds/overlaps, stable slots, DNS targets, firewall ordering, inventory/role restrictions, SDN repair/apply lifecycles, and host-file repair/service triggers. Provider mocks cannot prove real packet filtering, systemd command execution, Pi-hole behavior, or reboot persistence. Those checks remain in the [deployment guide](deployment.md).

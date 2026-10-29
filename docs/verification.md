# Implementation verification

This repository contains Terraform configuration and native Terraform tests. No Proxmox, Pi-hole, or EdgeRouter deployment has been performed.

The 2026-10-29 scope corrections removed the custom deployment wrapper, host helpers, and Pi-hole wildcard file/service module. Host routing uses Terraform-managed Proxmox systemd files/services. DNS uses explicit local records through the Pi-hole API and the `dns_records` module, with no Pi-hole SSH access. New guests default to stopped, with inspection and first start performed in separate ordinary Terraform applies.

Run `make init` and `make check` to initialize the pinned providers, check formatting, validate every configuration, and run mock-provider tests. These checks do not connect to live infrastructure.

Verified on 2026-10-29 with Terraform 1.14.8: all eight configurations validate, all 32 Terraform tests pass, recursive formatting passes, and Git whitespace checks pass. No project source files require Python.

The tests exercise address bounds/overlaps, stable slots, DNS targets, firewall ordering, inventory/role restrictions, SDN repair/apply lifecycles, and host-file repair/service triggers. Provider mocks cannot prove real packet filtering, systemd command execution, Pi-hole behavior, or reboot persistence. Those checks remain in the [deployment guide](deployment.md).

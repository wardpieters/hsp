---
title: 2. Deployment
description: Follow the deployment guide from prerequisites to acceptance and removal.
---

# 2. Deployment

The [deployment guide](../deployment.md) describes the full Terraform workflow. Follow the sections in order for a new installation; return to the LXC and bootstrap sections when adding guests later.

## Chapter index

1. [Prerequisites](../deployment.md#prerequisites) — inventory, templates, credentials, backups, and host access.
2. [Configure and initialize](../deployment.md#configure-and-initialize) — shared settings, provider initialization, local checks, and initial guest settings.
3. [Extra VM disks](../deployment.md#extra-vm-disks) — data disks, storage overrides, backups, and mounting inside the guest.
4. [LXC guests and storage](../deployment.md#lxc-guests-and-storage) — templates, mount volumes, backups, nesting, SSH, and migration.
5. [Apply Proxmox host routing](../deployment.md#apply-proxmox-host-routing) — forwarding, aggregate routes, and startup ordering.
6. [Declare local DNS records](../deployment.md#declare-local-dns-records) — explicit Pi-hole records and wildcard migration.
7. [Provision stopped guests](../deployment.md#provision-stopped-guests) — saved plans, routing outputs, and stopped-guest inspection.
8. [Start inspected guests](../deployment.md#start-inspected-guests) — activation after inspection.
9. [Bootstrap guest SSH](../deployment.md#bootstrap-guest-ssh) — temporary setup access.
10. [Debian guest setup](../debian-setup.md) — login proxy variables, APT downloads, and Docker proxy and log rotation settings.
11. [Live acceptance and removal](../deployment.md#live-acceptance-and-removal) — packet checks, persistence, and cleanup.

Use the [firewall and access chapter](firewall.md) alongside this guide when configuring services and dependencies.

- [Optional HE tunnel, port forwards, egress and cutover](../ipv6.md)

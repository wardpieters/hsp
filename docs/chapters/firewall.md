---
title: 3. Firewall & access
description: Find role permissions, firewall ordering, and the settings that add access.
---

# 3. Firewall & access

The [role and firewall reference](../firewall-roles.md) documents the policies generated for both VMs and LXCs. Start with roles and shared rules, then look up the setting for the access you need.

## Roles and policy

1. [Roles](../firewall-roles.md#roles) — automatic permissions and restrictions for each guest role.
2. [Shared rules for every role](../firewall-roles.md#shared-rules-for-every-role) — default policies, source filtering, DNS/NTP, and protected ranges.
3. [Settings that add permissions](../firewall-roles.md#settings-that-add-permissions) — dependencies, bootstrap access, public ports, egress, and proxy selection.

## Access configuration

- [Existing servers during migration](../firewall-roles.md#access-to-existing-servers-during-migration)
- [LAN access to public ports](../firewall-roles.md#lan-access-to-public-ports)
- [LAN access to private services](../firewall-roles.md#lan-access-to-private-services)
- [Outbound internet ports](../firewall-roles.md#outbound-internet-ports)
- [NTP pools](../firewall-roles.md#ntp-pools)
- [Shared HTTP forward proxy](../firewall-roles.md#shared-http-forward-proxy)

## Ordering and inspection

- [Guest rule order](../firewall-roles.md#guest-rule-order)
- [Proxmox host management and VPN clients](../firewall-roles.md#proxmox-host-management-and-vpn-clients)
- [Inspect the generated configuration](../firewall-roles.md#inspect-the-generated-configuration)

Continue with [verification](verification.md) to understand the checks behind the configuration.

- [IPv6 DNAT, effective egress and isolation](../ipv6.md)

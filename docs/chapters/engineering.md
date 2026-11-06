---
title: 5. Engineering records
description: The original designs and implementation plans, grouped by feature.
---

# 5. Engineering records

These documents preserve the project's design and implementation history. They contain the original requirements, decisions, planned steps, and verification expectations. Earlier plans can describe approaches that were subsequently revised; use the current deployment and firewall guides for operations.

## Chapter index

| Feature | Design | Implementation plan |
| --- | --- | --- |
| Managed-guest IPv6 hairpin (planned) | [Explicit grants and gateway SNAT](../superpowers/specs/2026-11-06-ipv6-hairpin-design.md) | [Hairpin implementation](../superpowers/plans/2026-11-06-ipv6-hairpin.md) |
| Self-hosting infrastructure | [Architecture and scope](../superpowers/specs/2026-10-28-self-hosting-infrastructure-design.md) | [Infrastructure implementation](../superpowers/plans/2026-10-28-self-hosting-infrastructure.md) |
| LXC support | [Guest types, storage, and migration](../superpowers/specs/2026-10-30-lxc-support-design.md) | [LXC implementation](../superpowers/plans/2026-10-30-lxc-support.md) |
| LXC nesting API | [Token-based feature ownership](../superpowers/specs/2026-10-30-lxc-nesting-api-design.md) | [Nesting API implementation](../superpowers/plans/2026-10-30-lxc-nesting-api.md) |

For current behavior and recorded outcomes, return to [deployment](deployment.md), [firewall and access](firewall.md), or [verification](verification.md).

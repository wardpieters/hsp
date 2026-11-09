# Automatic IPv6 public forwarding and hairpin

**Status:** Approved on 2026-11-09.

## Intent

With HE IPv6 enabled, `guests[*].public_ports` is the sole source of public
TCP and UDP forwarding. Managed-guest hairpin requires matching effective
internet egress or an explicit directed guest-to-guest connection on the
forwarded protocol/port, as clarified by the user on 2026-11-09. Self-hairpin
also requires matching egress.
Remove `port_forwards` and `hairpin` from both root input schemas and the
shared IPv6 tfvars and example.

## Approach

Derive forwarding and source-to-forward hairpin entries in the home root,
and extend the existing ingress, service and VM interfaces to carry protocol
alongside port. This reuses the current DNAT, target-gateway SNAT, firewall
and revocation machinery. Keeping manual allowlists would contradict the
requested automatic behavior; a separate UDP implementation would duplicate
the existing routing lifecycle. The user confirmed UDP belongs in scope.

## Behavior and constraints

- A protocol/port pair must have exactly one guest owner. Reject conflicting
  ownership during planning. TCP and UDP may use the same port number,
  including on different guests. Deduplicate repeated declarations by the
  same owner.
- Use deterministic forward keys such as `tcp-443` and `udp-53`, and hairpin
  keys combining source guest and forward key. Outputs report the actual
  protocol and resolved target.
- Participants are public forward targets, guests with effective internet
  egress and sources with authorized hairpin connections. Authorize a hairpin
  tuple only when its protocol/port matches effective source egress OR an
  explicit `connections` entry matches source, resolved target, protocol and
  port in that direction. Role-generated IPv4 connections do not qualify.
  Continue validating participant slots. HE disabled yields no entries.
- Preserve exact guest/VNet matching, self-hairpin, target-gateway SNAT,
  firewall bridge connection zones and protected destination filtering.
  Hairpin does not grant general internet egress or direct guest access.
- Carry protocol through NAT, native firewall rules, permission manifests,
  connection enumeration and cleanup. Removing or moving a UDP forward must
  revoke its UDP flows without deleting TCP flows on the same port, and vice
  versa. Continue accepting existing TCP permission manifests.
- Preserve existing management-port restrictions. LAN/VPN client prefixes,
  IPv4 hairpin, DNS changes and live deployment are outside this change.

## Verification

Add Terraform coverage for derived TCP/UDP targets, permission-scoped and self
hairpin, guests without egress, conflicts, same-number different protocols,
empty declarations and HE disabled. Extend helper tests for UDP rendering,
tuple parsing, targeted cleanup and protocol isolation. Update operator
documentation and run the repository checks. Offline checks do not establish
Linux live acceptance.

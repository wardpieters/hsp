# Managed-guest IPv6 hairpin design

**Date:** 2026-11-06

**Status:** Approved on 2026-11-06; implemented and offline verified. Linux
live acceptance remains pending.

**Baseline:** [HE IPv6 design](2026-11-05-he-ipv6-design.md), including the
2026-11-06 corrections for legacy firewall bridge tracking (`c364523`).

## Intent and agreed scope

Allow explicitly selected managed VMs and LXCs to reach existing HE public
TCP forwards through the shared public IPv6 address. Support both one guest
calling another and a guest calling its own public service. The connection
stays on Proxmox rather than travelling through the HE tunnel.

The user selected managed guests only, gateway SNAT, and explicit
guest-to-forward grants. LAN/VPN client prefixes, Proxmox-originated clients,
IPv4 hairpin, UDP forwarding, direct ULA dependencies, and DNS changes are
outside this extension. A VPN gateway guest can be an explicitly granted
client, but Terraform does not configure VPN client routing or translation;
only traffic bearing that guest's exact assigned ULA is eligible.

This document records the approved implementation contract. Operator guides
describe the implemented behavior; deployment and Linux live acceptance are
separate operator steps, not outcomes proven by offline tests.

## Current behavior and constraints

`environments/home/ipv6.tf` allocates ULA networking to forward targets and
guests with effective internet egress. `modules/ipv6_ingress` owns the
`ip6 hsp_he_ingress` table, DNAT from `hsp-he6`, internet SNAT, forwarding
guard, permission manifest and scoped conntrack cleanup. Native guest
firewalls drop protected IPv6 ranges before public and internet allowances.
The public VIP is itself protected, so internet TCP permission alone cannot
make a guest a hairpin client.

Legacy `fwbr<VMID>i0` bridge traversals use zone 1 before connection
tracking; routed NAT uses zone 0. Preserve those corrections. Never revert
to an all-zone-0 design or wildcard bridge ownership.
The host-config root independently protects INPUT to the VIP and ULA
gateways. Unmapped hairpin attempts must still hit that host protection.

## Approaches

| Approach | Benefit | Cost / decision |
| --- | --- | --- |
| DNAT and SNAT every granted hairpin connection to the target ULA gateway | One path for cross-guest and self-hairpin; replies return through NAT | Backend sees gateway identity; **selected by the user** |
| Preserve cross-guest sources; SNAT only self-hairpin | Cross-guest application logs retain client identity | Two policy/translation paths and exceptional self-hairpin cleanup; declined |

Split DNS would change name resolution rather than provide public-VIP
hairpin connectivity, so it does not satisfy this request.

## Configuration contract

Add the following field to the shared `he_ipv6` object in BOTH root schemas:

```hcl
hairpin = optional(map(set(string)), {})
```

Keys are source guest names; values are nonempty sets of existing
`port_forwards` keys. Example fragment inside an enabled `he_ipv6` object:

```hcl
port_forwards = {
  https = { guest = "proxy-public", port = 443 }
  imaps = { guest = "mail", port = 993 }
}
hairpin = {
  monitoring   = ["https", "imaps"]
  proxy-public = ["https"] # Self-hairpin is supported.
}
```

These are independent application permissions. They do not require or add
`internet_egress_ports`, and internet permissions do not imply hairpin
access. Roles never generate hairpin grants automatically. An explicit
grant is an operator-authorized exception to protected-destination denial,
including for a gateway with a restrictive role; it opens only the named
public forward. The destination must retain the baseline declared TCP
`public_ports` prerequisite. No port remapping is introduced.

Both roots validate source names against `^[a-z][a-z0-9-]{0,62}$`, referenced
forward keys against `^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$`, nonempty sets and
referenced forward existence while HE is enabled. Do not add restrictions
to unreferenced baseline forward keys. Home additionally validates source guest
existence and slots <=65535 for all participants. Host-config has no guest
inventory and therefore cannot validate source existence. With HE off,
well-typed saved settings may reference absent guests/forwards, consistently
with the baseline off-state contract. Malformed values must fail with
blocking validation, not warning-only checks.

Participants become the union of forward targets, nonempty effective-egress
guests, and configured hairpin source guests. A hairpin-only source receives
its slot-derived ULA /64, gateway offset 1 and guest offset 2, plus its exact
owned firewall bridge. It receives no internet or public-listener grant.
Removing its final reason to participate removes that IPv6 network through
the existing SDN lifecycle. Deduplicate grants and sort rendered manifests.

## Packet and identity contract

For source guest A, target B and public TCP port P:

| Point | Request tuple |
| --- | --- |
| A before routing | `A_ULA:client_port -> VIP:P` |
| Routed prerouting | DNAT `VIP:P` to `B_ULA:P` |
| Routed postrouting | SNAT source to `B_gateway:translated_client_port` |
| B's application | `B_gateway:translated_client_port -> B_ULA:P` |
| Reply delivered to A | `VIP:P -> A_ULA:client_port` |

Permit the kernel to choose a different translated source port when
necessary; multiple clients using the same source port must coexist.
Apply this exact contract when A equals B. Do not SNAT external HE ingress;
those applications continue seeing their real external client IPv6.

Use only the existing `hsp_he_ingress` table and service. Generate prerouting
hairpin DNAT matching the exact source VNet, exact source /128, VIP /128 and
granted TCP port. These rules must apply at the routed zone-0 traversal,
not on the intermediate firewall bridge traversal. Generate postrouting
SNAT only for the corresponding DNAT tuple and exact target VNet/address,
using the target's assigned ULA gateway. Never masquerade the ULA aggregate.

The forward guard authorizes the CURRENT resolved source-to-target grant,
matching original source/VIP/protocol/port, translated target, direction and
routed interfaces. Match the original request before SNAT has happened;
do not require the first forward-hook packet to already have SNAT status.
Authorize replies by the same connection tuple. Scope the existing public
DNAT accepts to actual HE original/reply paths so they cannot accidentally
admit an ungranted hairpin tuple. A blanket `ct state established accept`
or a blanket `ct status dnat accept` is insufficient.

Retain invalid/control-traffic drops, narrow local NDP and authorized
related ICMPv6 error handling. A valid ICMPv6 error may arrive from a router
outside the application's two endpoint addresses; tie authorization to the
granted master tuple rather than requiring that router to be a guest.
Unrelated errors and new ICMP sessions gain no hairpin permission.

## Native guest firewall contract

Pass two new inputs through `service_vm` to `vm`, both defaulting to `[]`:

```hcl
ipv6_hairpin_out = list(object({ public_address = string, port = number }))
ipv6_hairpin_in  = list(object({ gateway = string, port = number }))
```

For each source, outgoing rules allow TCP to the exact VIP /128 and granted
port before protected-destination drops. For each target with at least one
grant, incoming rules allow TCP from its exact gateway /128 to its own ULA
/128 and granted port before protected-source drops. Deduplicate target
rules shared by several clients. Validate addresses against the assigned
IPv6 network, valid ports and the target's `ipv6_forwarded_ports` subset;
reject nonempty hairpin policy without IPv6 networking.

Replies remain stateful. Preserve IP/MAC filtering, exact source address
sets, typed ICMP/NDP encoding, default DROP and all IPv4 policy. Host guard
acceptance does not override another chain's drop: offline tests must
assert native rule placement as well as nft generation. The router guard
is the authority preventing direct ULA access from clients; a native
gateway-source exception alone must never become a broad lateral grant.

## Internal module interface and outputs

Add `hairpin`, default `{}`, to `modules/ipv6_ingress`:

```hcl
map(object({
  source_guest   = string
  source_address = string
  source_vnet_id = string
  forward_key    = string
  target_guest   = string
  target_address = string
  target_vnet_id = string
  target_gateway = string
  port           = number
}))
```

Home resolves entries keyed by `source_guest/forward_key` (slash is excluded
from both name grammars). Validate each target against `forwards`, exact
ULA hosts and VNet syntax, and gateway offset 1 in the target /64. Include
hairpin sources when validating `firewall_bridges`. Instantiate the module
when any resolved forwarding, egress or hairpin entry exists.

Add home output `ipv6_hairpin`, `{}` when off or unconfigured. It has the
same composite keys and values `{ source_guest, source_address,
source_vnet_id, forward_key, public_address, protocol, port, target_guest,
target_address, target_vnet_id, translated_source_address }`.
`protocol` is `tcp`; `translated_source_address` is the target gateway.
Preserve every existing output shape. Host-config accepts the shared
configuration field but creates no hairpin resources or new host allowances.

## Revocation, failure recovery and compatibility

Extend the existing permission manifest with deterministic P records:

```text
H|VIP|ULA48
P|VIP|SOURCE|tcp|PORT|SOURCE_VNET|TARGET|TARGET_VNET|GATEWAY
```

The first line remains the existing topology header. Parse P lines by
their exact nine-field shape. Preserve existing D/E records and accept old
manifests without hairpin records. Record the union of old/new permissions
before exposure, and retain old records until cleanup succeeds. Bridge
migration cleanup must consider a guest appearing as source OR target.

On removing a grant, remapping its forward, changing its resolved tuple or
stopping the feature: first withdraw affected forwarding permission, then
purge the affected routed zone-0 and bridge zone-1 connection state. A
forward removal still purges its baseline external ingress. Removing only
one hairpin grant must preserve external ingress, internet egress and
other clients' grants/sessions, even when they share a target port.
Conversely, removing an internet E permission must preserve an independent
hairpin P grant on that same guest/protocol/port. Replace the baseline broad
zone-1 egress-source cleanup with exact connection selection where needed;
its current source/protocol/port selector would also match hairpin sessions.

Zone 1 has two views: source-side `SOURCE -> VIP` and target-side
`GATEWAY -> TARGET`. For precise cleanup, snapshot affected zone-0 tuples
after blocking and BEFORE deleting them; retain original and translated
TCP source ports. Use these to delete only corresponding zone-1 target
tuples, plus source-side tuples scoped by original source/VIP/port.
Persist the cleanup snapshot in the private runtime directory before any
deletion, and retain it until all deletions finish so a failed retry can
still remove target-side state after zone 0 is gone. Handle identical
self-hairpin endpoints and translated-port collisions without broad
target-port purges. Existing conntrack tooling plus POSIX shell/awk suffice;
do not add a host Python/jq dependency.

No-op reloads and additions preserve existing sessions. Failed reductions,
tuple enumeration, parsing or deletion retain the existing blocking guard
and report failure. Empty enumeration is successful; malformed output is
an error. Stop and the existing explicit teardown retry use the same
cleanup path. Never flush global conntrack or foreign tables. After a host
reboot kernel connections are gone; after a service restart durable runtime
records remain available under the existing runtime-preservation policy.

## Acceptance and rollout

Offline Terraform tests cover enabled/off validation, hairpin-only VM/LXC
participation, self/cross resolution, exact rules and ordering, output
shapes, removal of the final grant, and old configurations with `{}`.
Rendered-helper tests cover both zone-1 views, translated-port collisions,
selective revocation/remap, pending-snapshot retry, preflight/transaction
failure, stop and bridge-profile changes. Mocks prove generated commands
and lifecycle only; they do not simulate the Linux packet path.

Live acceptance is a separate operator step on Proxmox VE 9.x with the
existing firewall backend: compile native rules and run `nft -c`, then
verify cross-guest VM/LXC and self-hairpin TCP, application gateway identity,
two concurrent clients using the same source port, large transfers/related
ICMPv6, zero corresponding application packets on `hsp-he6`, and zone 0/1
tuples in both directions. Deny ungranted sources/ports, direct ULA, spoofed
sources, LAN sources, and host management. Verify active-grant revocation,
unrelated-flow preservation, firewall/service reload and reboot behavior.
External HE ingress must still preserve client identity and configured
internet TCP/UDP/ICMP must still work.

The shared file is still passed to both roots. Existing HE deployments
need only home changes for grants; host-config should plan no networking
change for the new field. Follow stopped-first guest provisioning and
configure a new ULA in an existing guest OS before testing; Terraform
cloud-init changes alone do not prove it is active. Grant removal requires
home apply, with SSH retained until cleanup succeeds. No live apply,
router change, public DNS publication or guest restart is authorized here.

## Global implementation constraints

- Managed guests only; hairpin grants default to `{}` and name existing TCP forwards.
- Use gateway SNAT for both cross-guest and self-hairpin; external HE ingress preserves client identity.
- Keep Terraform >=1.10 and <2.0 in home; >=1.9 and <2.0 in modules and host-config.
- Keep bpg/proxmox 0.118.1, neuspaces/system 0.5.0, lukaspustina/pihole 0.3.1 and magodo/restful 0.25.2.
- Keep the established pve-firewall backend, exact bridge zone 1 and routed NAT zone 0.
- Preserve IPv4 resources, internet-egress inheritance, existing output shapes and IPv4-only local DNS.
- Preserve all pre-existing checkout changes and private tfvars; stage only this feature's own changes.
- No global ruleset/conntrack flush, new host dependencies, automatic network/guest restart, live apply or router/DNS change.

## Builder discretion and references

Internal local names and shell function decomposition are builder choices.
The packet, permission, identity and selective-cleanup contracts above are
fixed. If actual bridge traversal cannot satisfy them, stop and revise the
design rather than weakening filtering or widening cleanup.

The combined hairpin behavior is a design inference from the existing
topology and these primary references; it still requires Linux acceptance:

- [nftables NAT, connection tuples and pre-tracking zone assignment](https://netfilter.org/projects/nftables/manpage.html).
- [conntrack original/reply tuple, port and zone selectors](https://netfilter.org/projects/conntrack-tools/conntrack-manpage.html).
- [Linux bridge netfilter traversal](https://cdn.kernel.org/doc/html/latest/networking/bridge.html).

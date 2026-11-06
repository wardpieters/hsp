# Optional Hurricane Electric IPv6 ingress and internet egress

Status: implementation complete and verified offline on 2026-11-06; live acceptance and deployment remain operator-owned.
The user selected Proxmox destination NAT instead of TCP proxying mail
through the public reverse proxy. This revision supersedes that earlier
architecture. The latest requirement also enables outgoing IPv6 according
to each guest's effective `internet_egress_ports`; both directions are
specified below. A fresh builder check of the egress additions reported
no important unresolved questions.

## Intent and scope

Expose selected TCP services on one public IPv6 address. Proxmox terminates
an existing Hurricane Electric (HE) 6in4 tunnel and performs IPv6 destination
NAT (DNAT): ports 80/443 go to `proxy-public`, while explicitly configured
mail ports go directly to a future mail guest. Each target keeps its own
isolated VNet, existing IPv4 configuration, and a separate private IPv6
(ULA) /64. Guests with effective internet egress permissions also receive
their own ULA /64, including guests with no public port forwards.
`mail.example.com` serves HTTPS through the reverse proxy and
SMTP directly through the mail server using the same public IPv6 address.

For incoming connections translate the destination only. Preserve the
external client's IPv6 source address and route replies back through
Proxmox for conntrack reverse translation. For permitted new outgoing
connections, source-NAT the guest's ULA to the same public VIP. Replies are
translated back to the originating guest. Mail TLS/STARTTLS terminates at
the mail server. TCP proxying and PROXY protocol are not required.

The user will disable the old tunnel endpoint and manually change the
EdgeRouter's protocol-41 NAT target to Proxmox. Do not access or migrate the
old endpoint or configure the router. Local DNS stays IPv4-only: do not edit
the Pi-hole DNS module, add local AAAA records, or change resolvers. Public
AAAA/MX publication, guest application setup and live cutover are operator
actions after verification. Do not create a mail guest, choose a mail stack,
run a live apply or restart guests as part of repository implementation.

## Existing implementation and alternatives

The host-config root manages IPv4 routing through `neuspaces/system` SSH
file/service resources. The home root owns Simple-zone VNets, VM/LXC
initialization, guest firewalls, optional whole-node firewall ownership and
local Pi-hole A records. Each guest uses its slot for an isolated IPv4 /30;
all IPv6 is currently explicitly denied. Preserve the existing IPv4 rules,
roles, dependencies, outputs and source filtering, including pre-existing
uncommitted work adding portless IPv4 ICMP egress.

Considered approaches:

1. Separate public guest addresses and MX: simple routing, but does not
   satisfy the same mail hostname for proxied HTTPS and mail protocols.
2. TCP proxying through `proxy-public`: permits IPv4-only mail backends but
   needs client-address propagation and makes SMTP depend on that proxy.
3. Proxmox IPv6 DNAT to isolated ULA guests: selected by the user. Preserves
   client identity without a TCP proxy; adds host NAT/conntrack lifecycle
   and internal IPv6 to each forwarding target.

Keep HE termination on Proxmox so routing and DNAT are Terraform-managed.
Use IPv6 DNAT for incoming TCP forwards and explicit IPv6 SNAT for permitted
guest-initiated TCP/UDP/ICMP traffic. SNAT uses the fixed public VIP, not
interface-address masquerading. NAT64, NDP proxying, native IPv6 uplinks,
DHCPv6 and SLAAC remain out of scope. The current HE /64 is sufficient;
a /48 is not required. HTTP backends may stay IPv4-only when they have
neither public forwarding nor effective internet egress permissions.

## Addressing and packet path

```text
HE server 216.66.84.46
  -> protocol 41 -> EdgeRouter WAN 178.226.181.114
  -> manual DNAT of protocol 41 -> Proxmox 192.168.100.10
  -> hsp-he6: 2001:470:1f14:4d4::2/64
  -> shared public VIP on hsp-vip6: 2001:470:1f15:4d6::2/128
     TCP 80/443 -> DNAT -> proxy-public, fd42:77:1:2::2
     configured mail TCP ports -> DNAT -> future mail guest's ULA

permitted guest TCP/UDP/ICMP -> Proxmox -> SNAT to public VIP -> HE -> Internet
```

`hsp-he6` is a SIT interface; `hsp-vip6` is an HSP-owned dummy interface.
HE's server IPv6 is `2001:470:1f14:4d4::1`. The tunnel-link prefix (`1f14`)
is distinct from the routed service prefix (`1f15`). The SIT local IPv4 is
Proxmox's actual LAN address, not the router's public IPv4. The router must
allow and translate IP protocol 41 in both directions to/from HE's server;
this is not TCP/UDP port 41.

Derive the public VIP at offset 2 of the routed /64. Assign ONLY that /128
to the host dummy interface. Do not place the public /64 on any guest VNet.
Install an owned blackhole route for the rest of the routed /64 so unused
destinations cannot follow the default route back to HE.

Configure one stable, operator-selected ULA /48, illustrated as
`fd42:77:1::/48` (choose a unique RFC4193 Global ID for a real deployment).
For each participating guest, derive `cidrsubnet(ula_prefix, 16, slot)`;
gateway offset 1, guest offset 2. Slot 2 gives `fd42:77:1:2::/64`, gateway
`fd42:77:1:2::1`, guest `fd42:77:1:2::2`. A hypothetical future mail guest in
slot 16 would get `fd42:77:1:10::2`; do not allocate that slot/guest now.
Participants are the union of forwarding targets and guests with a nonempty
effective internet-egress list. That list is the existing deduplicated
global + per-guest + role-default list (including monitoring TCP 80/443).
For example, global UDP 123 makes every guest an IPv6 egress participant
while HE is enabled. Guests with neither receive no IPv6. Never reuse one
/64 across isolated VNets; changing list order must not renumber guests.

Expected host routes include:

```text
local 2001:470:1f15:4d6::2/128 dev hsp-vip6 table local
2001:470:1f14:4d4::/64 dev hsp-he6
fd42:77:1:2::/64 dev hsp1002
blackhole 2001:470:1f15:4d6::/64 metric 42761
default via 2001:470:1f14:4d4::1 dev hsp-he6 metric 42761
```

Guests use their ULA gateway as the IPv6 default gateway. An incoming packet
is DNATed before route selection, crosses the appropriate VNet and retains
its original global source. The guest's reply goes through Proxmox, where
conntrack rewrites its ULA source back to the public VIP. New outgoing
connections require an effective internet-egress permission and a public
destination outside protected ranges. Proxmox SNATs permitted flows to
the VIP and returns replies to the correct ULA guest. Public ingress does
not itself grant outgoing initiation, and outgoing access does not open
an incoming listener. Host-originated IPv6 may use the host-wide HE default
route, subject to host filtering. Existing IPv4/default routes remain.

## Shared configuration and global toggle

Both roots accept an identical non-nullable `he_ipv6` object, default `{}`:

```hcl
he_ipv6 = {
  enabled         = true
  server_ipv4     = "216.66.84.46"
  local_ipv4      = "192.168.100.10"
  client_ipv6     = "2001:470:1f14:4d4::2/64"
  server_ipv6     = "2001:470:1f14:4d4::1"
  routed_prefix   = "2001:470:1f15:4d6::/64"
  ula_prefix      = "fd42:77:1::/48"
  mtu             = 1480
  protected_cidrs = []
  port_forwards = {
    http  = { guest = "proxy-public", port = 80 }
    https = { guest = "proxy-public", port = 443 }
    # Add only AFTER declaring a ready mail guest and its public_ports:
    # smtp = { guest = "mail", port = 25 }
  }
}
```

Exact schema:

```hcl
object({
  enabled         = optional(bool, false)
  server_ipv4     = optional(string)
  local_ipv4      = optional(string)
  client_ipv6     = optional(string)
  server_ipv6     = optional(string)
  routed_prefix   = optional(string)
  ula_prefix      = optional(string)
  mtu             = optional(number, 1480)
  protected_cidrs = optional(list(string), [])
  port_forwards   = optional(map(object({ guest = string, port = number })), {})
})
```

`he_ipv6.enabled` is the ONE global on/off toggle. Ship a disabled
`environments/he-ipv6.tfvars.example` with portable documentation-range
addresses. Copy to the already-ignored `environments/he-ipv6.tfvars` and pass
the SAME file to both roots with `-var-file=../he-ipv6.tfvars`. Do not edit
private tfvars. Two states are not atomic: enable host-config then home;
disable home then host-config. Editing the file alone changes nothing.
Omitting it selects off and can plan removal of a deployed HE setup.

Forwarding keys identify stable declarations. Only TCP and same-number
external/backend ports are supported initially. Each public port is unique
across the map, is an integer 1..65535, and excludes 22/8006. Home validates
that every target exists and its EXISTING
`public_ports` explicitly includes that TCP port. Existing role restrictions
therefore continue to apply. Every participant, including egress-only
guests, must have a slot at most 65535. An empty forwarding map is valid:
egress-only guests still get IPv6 and SNAT. Only when BOTH forwarding and
effective egress are empty are no guest IPv6 networks/NAT service created;
the guarded host VIP/tunnel may remain enabled. Undeclared future mail
targets are rejected rather than implicitly provisioned.

No new egress flag or parallel egress list is introduced. With HE enabled,
the existing effective `internet_egress_ports` controls both families: TCP
and UDP match their configured destination ports; portless `icmp` means
IPv4 ICMP plus IPv6 ICMPv6. Required IPv6 errors/NDP work independently;
explicit router-control/redirect and protected-network denials still take
precedence over an internet ICMPv6 permission. With HE off, existing IPv4
behavior and IPv6 denial remain. Fixed DNS/NTP exceptions stay IPv4 and do
not independently select guests for IPv6; IPv4 DNS transport may return
public AAAA answers for these guests without adding any local AAAA record.

Enabled common validation rejects missing/null endpoints, address-family
confusion, multiline/shell-injection strings, noncanonical/wrong-sized
prefixes, overlapping tunnel/service prefixes, identical client/server
addresses or a server outside the client's tunnel /64, invalid port entries
or duplicate public ports, and MTUs outside integer 1280..1480. The routed
prefix is a global-unicast /64 in `2000::/3`; the ULA prefix is canonical
`fd00::/8` space with length /48. Extra protected CIDRs are canonical IPv6.
Home also requires `local_ipv4 == host_address` and valid `proxmox_ssh`.
Use blocking validation/preconditions, not warning-only checks. When off,
well-typed saved settings do not require live/matching target guests.

## Terraform ownership and resource boundaries

Reuse pinned `neuspaces/system` 0.5.0 in BOTH roots. Home adds this existing
repository provider to its requirements/lockfile and uses its existing
optional `proxmox_ssh` connection for a dedicated ingress module. Enabled
forwarding requires SSH to the same Proxmox node. Fresh/default-off
configurations must not initialize SSH sessions or require SSH settings.
Disabling an already-deployed feature DOES require SSH for resource cleanup;
retain the same SSH connection settings until teardown completes. No new
provider versions, networkd takeover, or overwriting Proxmox-generated
network files. Final review required one narrow exception to the original
no-new-provisioners constraint: two destroy-only SSH agent remote-exec gates
explicitly stop the service and rerun its idempotent helper before Terraform
can delete cleanup files. Systemd skips ExecStop for a failed/inactive unit,
so relying only on service deletion cannot make failed teardown retryable.
The gates save connection metadata in state, add no private keys/passwords,
and do not run during creation or ordinary reconciliation. On Proxmox require iproute2, sysctl, POSIX shell, `nft` and
`conntrack` userspace tools; document these prerequisites rather than silently
installing packages. No Python/jq dependency on Proxmox.

Host-config / `modules/proxmox_host` owns:

- `hsp-he6`, `hsp-vip6`, tunnel/VIP addresses, reserved metric-42761 default
  and blackhole routes, persistent IPv6 forwarding, and its own files/unit.
- A dedicated nftables `ip6 hsp_he_host` table for host INPUT protection.
  Install this guard BEFORE bringing up the public VIP or tunnel. Permit
  required ICMPv6 errors and narrowly scoped ULA NDP; reject remaining host
  input arriving on the HE tunnel or targeting the VIP/ULA gateway space.
  No public Proxmox GUI/SSH/listeners may become reachable when ports are
  unmapped, even with `manage_host_firewall = false` or the home root absent.

Home / new `modules/ipv6_ingress` owns:

- A separate nftables `ip6 hsp_he_ingress` table containing prerouting TCP
  DNAT, explicit postrouting SNAT and forwarding guard chains, plus its
  own helper/unit/files. The module name remains `ipv6_ingress` for this
  single shared IPv6 edge; it manages both directions. Its new `egress`
  input is `map(object({ address = string, vnet_id = string, ports =
  list(object({ protocol = string, port = optional(number) })) }))`, keyed
  by guest name, containing only nonempty effective lists. Instantiate
  the module whenever either incoming forwards or egress is nonempty.
- Rules match `iifname hsp-he6`, the exact public /128, and declared TCP
  ports, then translate to resolved ULA /128 targets with the same port.
  No broad destination rewrite or wildcard target exists.
- Egress entries resolve effective permissions to exact guest ULA /128,
  VNet, protocol and optional destination port. After protected-destination
  and control-traffic exclusions, allow only those new outgoing flows via
  `hsp-he6` and SNAT them to the fixed VIP. Never SNAT incoming client
  packets or apply a general ULA-to-internet accept/masquerade rule.
- Forwarding permits approved ingress/egress tuples and their established/
  related return/error traffic, including translated ICMPv6 errors/PMTU.
  Match original conntrack direction/guest/destination/protocol/port against
  CURRENT permissions; established state alone cannot bypass revocation.
  All other new traffic from HE, lateral ULA traffic, protected destinations
  and unapproved outgoing traffic are denied. Inbound replies to SNATed
  flows are permitted without requiring a public port forward.
- Its service starts only after the guest SDN and firewall resources have
  applied. No dependency from `pve-guests.service` on HE availability.

The two roots never own the same nftables table, address or service. Host
INPUT guards remain active while the VIP exists, including between root
applies and while the home DNAT service stops. Home's forwarding guard is
separate from optional whole-node Proxmox firewall ownership. Neither root
flushes the full nftables/iptables ruleset or replaces `pve-firewall`.

Use native nftables tables alongside the established iptables-based
`pve-firewall`; this does not enable `proxmox-firewall` or switch its backend.
The routed HE IPv6 conntrack zone is 0; exact participating legacy firewall
bridges use zone 1 before tracking. Existing IPv4 SNAT zone rules remain untouched. ULA subnets have `snat = false`; preflight must identify
conflicting IPv6 conntrack-zone/NAT rules and stop with actionable guidance
instead of blindly applying broad `fwbr+` zone rules. Verify the effective
zone on request AND reply paths during live acceptance.

## Lifecycle, reconciliation and fail-closed cleanup

Host and ingress helpers each expose `start|reload|stop`. Manage root-owned
scripts/unit files with `system_file`/`system_service_systemd`, private
runtime ownership markers/manifests, strict validated input, and no eval.
Refuse unrelated interface/table/route name collisions before mutation;
stop tolerates missing owned objects but never deletes a foreign replacement.
Use atomic nftables transactions scoped to the owned table. Validate before
replacement; partial failures retain or establish a blocking guard and
remove partially exposed owned networking. Preserve unrelated networking.

Persist `net.ipv6.conf.all.forwarding=1`; remove only HSP's sysctl file on
disable and do not force global forwarding to zero. Start after
network-online and pve-firewall, ensure SIT/dummy capability, and never
restart networking, guests or `pve-guests.service`. File repair/config
changes reconcile once; subsequent applies converge. Host tunnel setup
must not require guest VNets to exist. On host teardown, withdraw public
addresses/transport before removing their INPUT guard.

NAT rules affect connection establishment; deleting rules alone does not
remove existing translations. For removed/remapped forwards, atomically
revoke their forwarding permission and DNAT rule, then delete only affected
IPv6 TCP conntrack entries by old public destination/port in zone 0.
For revoked egress permissions, block affected directions and purge only
the affected guest's source-NATed flows by original ULA source, protocol,
original destination port when applicable, translated VIP and zone 0.
ICMPv6 has no transport-port selector. Do not purge other guests, protocols,
ports, retained role/global grants or unrelated host traffic. Retain
unchanged sessions on no-op reload. Stop first blocks new feature traffic,
purges all owned DNAT and TCP/UDP/ICMPv6 SNAT translations, then removes
its own table. If conntrack cleanup fails, retain the blocking guard and return an error;
do not report clean disable. Never flush all host connection tracking.

Changing the routed prefix, ULA aggregate or selected guests' slots requires
the documented disable/apply-both/reconfigure/enable cycle. Do not attempt
an uncoordinated in-place migration across roots. Tunnel endpoints and MTU
can reconcile in place while removing stale owned state. A runtime manifest
records old owned settings for cleanup even after rendered inputs change.

## SDN and guest policy

Home derives participants from the union of `port_forwards` targets and
nonempty effective global/per-guest/role internet-egress lists. Use the
SAME deduplicated effective lists already passed into service_vm; do not
implement different inheritance for IPv6. Pass nullable
`ipv6_cidr` through `platform_network.networks` into `guest_network`, deriving
the per-slot ULA /64 in home. Add a separate counted IPv6 subnet resource;
retain the IPv4 subnet resource identity. Include IPv6 create/change/repair/
removal in centralized SDN apply generation without perpetual reapplication.
Return nullable `network.ipv6 = { cidr, gateway, address }` through
service_vm/vm and render static VM/LXC IPv6 initialization only when set.

Pass `ipv6_forwarded_ports = list(number)`, default `[]`, and
`protected_ipv6_cidrs = list(string)`, default `[]`, through service_vm/vm.
The first contains only this guest's mapped TCP ports and must be a subset
of its declared TCP `public_ports`. Protected ranges include the entire ULA
aggregate, routed public prefix, tunnel-link prefix and configured extras.

Maintain default DROP, IP/MAC filtering, DHCP disabled and `radv = false`.
Keep automatic `ndp = false` and explicitly allow local NS/NA (ICMPv6
135/136), DAD solicitation from `::/128`, and necessary ICMPv6 errors
(1/2/3/4). Scope NDP to the guest/gateway/link-local/solicited-node multicast
on its own VNet. Drop other unspecified-source traffic. Block IPv6
application traffic to/from ULA, local/loopback, link-local, multicast,
public/tunnel protected ranges before accepting mapped inbound TCP ports
or configured outgoing TCP/UDP/ICMPv6. Replies are stateful. Reuse the
existing effective `internet_egress_ports` in VM policy for IPv6 too; no
new guest egress input is required. Map `icmp` to `icmpv6` with no port,
while keeping explicit RA/RS/redirect and nonlocal NDP denials ahead of
that allowance. No new incoming ping is granted: replies to permitted
outgoing ping are stateful. Existing IPv4 ICMP and dependencies are unchanged.

The managed source set adds assigned ULA and `::` for DAD alongside IPv4;
the following unspecified-source drop prevents use outside DAD. Preserve
Proxmox's implicit MAC-derived link-local filtering; never allow a whole
ULA /64 as guest source. Verify template link-local behavior and DAD live.
No SLAAC, DHCPv6, RA, redirect, automatic incoming ping, peer IPv6 application
access or IPv6 VPN/monitoring guest dependencies are added; their effective internet
egress permissions still apply. With no IPv6 network, retain
the existing blanket IPv6 denial and single managed IPv4 source entry.

The existing SINGLE Proxmox node-rules owner is extended with required
HE-source protocol-41 and narrow control allowances only when
`manage_host_firewall = true`. When false, output the equivalent acceptance
requirements for the operator; do not silently take ownership of node
rules. Independent nftables guards still enforce the HE-specific denies
above; their accepts do not override drops in other firewall chains.

## MTU, applications and DNS

Default tunnel MTU 1480 assumes a 1500-byte IPv4 path; configurable minimum
is 1280. Do not change the shared zone/all NIC MTUs or hide PMTU failures
with blanket MSS clamping. Account for translation of related ICMPv6 errors
and quoted packet headers in acceptance tests, not merely TCP handshakes.

Mapped applications must listen on their assigned ULA addresses and reply
through their ULA gateway. HTTPS still terminates at the public reverse
proxy; its ordinary IPv4 `connections` to the mail GUI/other web backends
are unchanged. SMTP/submission/IMAP are direct kernel-forwarded TCP paths;
test original-client IPv6 visibility without PROXY headers. Optional mail
ports 25/465/587/993 are examples, never automatic defaults. HE filters TCP
25 by default; the operator arranges removal before relying on SMTP.
Outgoing IPv6 SMTP is supported when its destination port is allowed by
effective `internet_egress_ports` and HE permits it. Reverse DNS, SPF and
delivery reputation/configuration are separate operator responsibilities;
all SNATed guests share the public VIP as their outgoing IPv6 source.

After verification, public DNS can publish `mail.example.com AAAA
2001:470:1f15:4d6::2`, `example.com MX 10 mail.example.com` and web AAAA records
to that same VIP. Existing A records/local Pi-hole records and DNS outputs
are untouched. A LAN without IPv6 continues using its local A records;
LAN/VPN IPv6 hairpin forwarding is out of scope.

## Outputs, cutover and verification

Keep existing `guests`, `router_route`, `public_forwards`, `dns_targets` and
local DNS output shapes. New outputs describe desired state, not health:

- Home `ipv6_ingress`: null off, otherwise `{ public_address, routed_prefix,
  ula_prefix }`; `ipv6_networks`: map of participating guests to
  `{ vnet_id, cidr, gateway, address }`, empty off.
- Home `ipv6_port_forwards`: map keyed like the config, each value
  `{ public_address, protocol, port, guest, target_address, vnet_id }`, empty
  off. `protocol` is always `tcp`.
- Home `ipv6_egress`: map of guests with effective IPv6 internet egress to
  `{ public_address, source_address, vnet_id, ports }`, where `ports` is the
  existing effective list of `{ protocol, port }` with null port for ICMP;
  empty off. `source_address` is the guest ULA before translation.
- Home `ipv6_host_requirements`: list of
  `{ purpose, direction, iface, source, destination, protocol, icmp_type }`,
  nullable selectors as appropriate; empty off. This reports additional
  acceptance needs, not a claim they were applied.
- Host-config `he_ipv6_status`: null off; otherwise
  `{ interface, vip_interface, public_address, local_ipv4, remote_ipv4,
  local_ipv6, remote_ipv6, ula_prefix, mtu, route_metric }`.

Prepare both saved plans from the SAME shared var-file. The user stops the
old endpoint BEFORE the first enabled host apply. Apply host-config, then
home; verify actual guest networking/listeners before the user moves NAT.
Expect a cutover outage. Test externally with forced IPv6 address selection
before public AAAA publication. Never intentionally run both HE endpoints.
New guests retain the stopped-first workflow; changed cloud-init does not
guarantee an existing running VM immediately changes its OS configuration.

To disable: withdraw public AAAA and respect TTLs, switch false, apply home
first (revoke DNAT/egress, purge both kinds of translations, restore IPv6
denial/remove ULA subnets), then host-config (withdraw tunnel/VIP/routes/guards). Remove the
manual router rule. No IPv4 services are removed. To return to the old
endpoint, complete new-endpoint teardown before restoring its NAT/startup.
Keep the ordered two-root procedure explicit; independent states cannot
guarantee atomic cutover or safely migrate topology by a single file edit.

Offline tests cover config/role/port validation, per-slot ULA stability,
VM/LXC propagation, effective egress inheritance, policy order/source sets,
mapped-port and TCP/UDP/ICMP egress revocation, ownership, SDN/file repair
and convergence, and enabled-to-disabled cleanup.
Execute rendered helpers with fake ip/sysctl/nft/conntrack commands; verify
transactions, state preservation, collision handling, revocation sequencing
and failures without running real networking commands. Add the new module
to Makefile init/check coverage. Run `make check`, `make docs-build` and
`git diff --check` after implementation.

Operator live acceptance must verify actual nft syntax/compiled Proxmox
rules and conntrack zone 0 in both directions, external HTTPS/ready mail,
real incoming sender IPs, SNATed outgoing TCP/UDP/ping and their replies,
protected/undeclared egress denial, related ICMPv6/large transfers, no input
access to Proxmox at VIP/tunnel/ULA gateways, cross-guest/spoofing/RA denial, unmapped ports,
mapping revocation on established connections, firewall reload and
guest/host reboots, and off-state cleanup with IPv4 still working. Mac-host
mocks do not prove Linux netfilter behavior; a tunnel UP flag is not health.

## References and builder discretion

Root/module interfaces, one host VIP, ULA derivation, incoming destination-only
TCP forwarding, effective-list-controlled TCP/UDP/ICMP egress SNAT,
default-off toggle, guards, cleanup, local DNS scope and manual
cutover are fixed. Internal local names, safe helper implementation and
test harness structure are builder choices. Stop and revisit the design if
the pinned provider/kernel cannot express the required filtering without a
backend switch or if existing IPv6 conntrack rules conflict.

- [HE FAQ](https://ipv6.he.net/certification/faq.php)
- [Linux tunnel semantics](https://man7.org/linux/man-pages/man8/ip-tunnel.8.html)
- [Linux forwarding sysctls](https://docs.kernel.org/networking/ip-sysctl.html)
- [Netfilter IPv6 NAT and connection tracking](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_%28NAT%29)
- [Scoped conntrack deletion](https://netfilter.org/projects/conntrack-tools/conntrack-manpage.html)
- [Proxmox networking and NAT zones](https://github.com/proxmox/pve-docs/blob/master/pve-network.adoc)
- [Proxmox firewall behavior](https://github.com/proxmox/pve-firewall/blob/master/src/PVE/Firewall.pm)
- [Pinned firewall provider fields](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_firewall_rules.md)

## Global implementation constraints

- Terraform >= 1.10 and < 2.0 in home; >= 1.9 and < 2.0 in reusable modules and host-config.
- Keep bpg/proxmox 0.118.1, neuspaces/system 0.5.0, lukaspustina/pihole 0.3.1 and magodo/restful 0.25.2.
- HE IPv6 defaults off; use the same shared var-file for both Terraform roots.
- One public /128 on Proxmox; isolated ULA /64 per ingress or effective-egress guest, derived from its slot; gateway offset 1, guest offset 2.
- Incoming TCP uses destination NAT and preserves client IPv6 sources; permitted outgoing TCP/UDP/ICMP uses explicit SNAT to the shared VIP.
- Reuse effective global/per-guest/role internet_egress_ports for IPv6; keep protected networks blocked and IPv4 behavior unchanged.
- Keep local DNS IPv4-only; do not edit modules/dns_records or publish public DNS.
- No live apply, automatic guest/network restart, router change or old-tunnel access.
- Preserve all pre-existing checkout changes and private tfvars; stage only this feature's own changes.
- Keep the established pve-firewall backend and existing IPv4 resource identities; never flush global rules or conntrack.

## Operator-tested corrections (2026-11-06)

A supplied packet capture shows permitted guest packets leaving `hsp-he6`
with a private source, confirming failed source translation. The original
all-zone-0 bridge assumption is superseded: exact participating legacy
`fwbr<VMID>i0` interfaces use zone 1 before connection tracking, while
routed NAT remains in zone 0. Derive bridge names from VM/CT IDs, never
from arbitrary VNet names; map each bridge to its assigned ULA for cleanup.
On adoption, migrate affected null-NAT bindings under a blocking guard.
On later bridge changes, purge only affected guest tuples; preserve
unchanged guests, permissions and unrelated tracking in both zones.

Keep native BPG firewall ownership. Portless outbound ICMP uses canonical
`ipv6-icmp`; typed rules keep the legacy `icmpv6`/numeric-dport encoding
because BPG 0.118.1 does not expose `icmp-type`. The operator explicitly
accepted the remaining typed-rule editor warning instead of introducing
helper files or an alternate ownership mechanism. No new Perl policy
helper/security-group architecture is included. No live apply, merge, push
or local VM/container test is part of this correction.

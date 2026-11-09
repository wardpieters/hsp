# Optional HE IPv6: public ports, internet egress and managed hairpin

HSP can terminate a Hurricane Electric (HE) 6in4 tunnel on Proxmox. It uses
one public IPv6 address for TCP/UDP port forwards and permitted guest internet
traffic. The feature defaults off. IPv4-only deployments need no new values.

Incoming TCP/UDP ports are destination-NATed to individual guests. Outgoing
TCP/UDP/ICMP is allowed by the existing effective `internet_egress_ports`
list and source-NATed to the shared public address. Incoming clients retain
their real IPv6 source address. Authorized managed guests can also
reach the public TCP/UDP forwards locally, including their own service. These
hairpin requests use the target ULA gateway as their source. Guest VNets
remain separate; this does not grant direct ULA access.

## Addressing and configuration

The tunnel's link /64 connects Proxmox to HE; the routed /64 supplies the
public service address. The host owns offset 2 of the routed prefix as a
/128 on `hsp-vip6`. The remaining public prefix is blackholed. Guest
addresses come from a separate, stable ULA /48, with one /64 per slot and
gateway/guest offsets 1/2. A routed /48 from HE is unnecessary.

The following are documentation addresses, not a working HE allocation. Replace
them with your own tunnel and routed-prefix details:

| Purpose | Value |
| --- | --- |
| HE server IPv4 | `203.0.113.1` |
| Router public IPv4 registered with HE | `198.51.100.10` |
| Proxmox LAN/local tunnel IPv4 | `192.0.2.10` |
| HE server/client tunnel IPv6 | `2001:db8:1::1` / `2001:db8:1::2/64` |
| Routed service prefix | `2001:db8:2::/64` |
| Shared public service address | `2001:db8:2::2` |
| Illustrative private aggregate | `fdab:cdef:1000::/48` |
| Proxy in slot 2: gateway / guest | `fdab:cdef:1000:2::1` / `fdab:cdef:1000:2::2` |

Choose a unique ULA /48 for your site and keep it stable. Public addresses
are never assigned to guest VNets. The Proxmox HE default route is host-wide;
host-originated IPv6 may also use it, subject to host filtering.

Copy [the shared example](../examples/he-ipv6.json.example) to `he-ipv6.json`
in your copied starter directory. Fill in your own allocation and change
`enabled` to true only for the planned cutover:

```json
{
  "enabled": true,
  "server_ipv4": "203.0.113.1",
  "local_ipv4": "192.0.2.10",
  "client_ipv6": "2001:db8:1::2/64",
  "server_ipv6": "2001:db8:1::1",
  "routed_prefix": "2001:db8:2::/64",
  "ula_prefix": "fdab:cdef:1000::/48",
  "mtu": 1480,
  "protected_cidrs": []
}
```

Both Terraform roots read this same JSON file; neither reads the other's state.
Keep it present for the lifetime of the deployment. The checked-in template is
disabled by default, so falling back to it can plan removal of an existing HE
deployment. Review both saved plans before applying.

Public forwarding is derived from each guest's `public_ports` in the home
configuration. For example:

```hcl
guests = {
  proxy-public = {
    vm_id = 1002
    slot = 2
    vnet_id = "hsp1002"
    public_ports = [
      { protocol = "tcp", port = 443 },
      { protocol = "udp", port = 443 },
    ]
  }
}
```

Every declared TCP/UDP port is forwarded to that guest while HE is enabled.
Each protocol/port pair must belong to one guest; conflicts cause a blocking
plan error naming the owners. TCP and UDP may share a port number, even
with different guest targets. Repeated declarations by one owner deduplicate.
Ports 22/8006 remain forbidden; public and target port numbers are identical.
No guest or application software is automatically installed.

Guests receive their slot's ULA network when they have public ports,
nonempty effective internet egress, or an authorized outgoing hairpin
connection. Global, per-guest and role egress defaults combine exactly as
for IPv4; monitoring inherits TCP 80/443. Global UDP 123 therefore gives
every guest IPv6 even without public ports. Egress-only guests receive
no incoming listener grant.

`{ protocol = "icmp" }` remains portless and also permits internet ICMPv6,
including outgoing ping, after protected-network and router-control drops.
Required NDP/DAD and ICMPv6 error messages work independently. There is no
separate IPv6-egress flag. Fixed DNS/NTP infrastructure exceptions remain
IPv4; local Pi-hole records remain IPv4-only. Public DNS queries over IPv4
can still return AAAA answers for internet destinations.

## Managed-guest hairpin grants

Hairpin permissions derive automatically from existing source permissions.
A managed VM or LXC can reach a declared public forward only when either:

- Its effective `internet_egress_ports` includes the forward's exact protocol
  and port (including global, per-guest and role egress defaults).
- An explicit `connections` entry names that source guest and the resolved
  target guest with the exact protocol and port, in that direction.

For example, TCP 587 egress does not permit hairpin HTTP on TCP 80. A
`{ from = "web", to = "proxy-public", protocol = "tcp", port = 80 }`
connection permits that public HTTP forward without granting internet HTTP.
TCP and UDP on the same number remain separate. Self-hairpin also requires
matching egress; self-connections remain invalid in the `connections` input.
Role-generated guest connections and fixed IPv4 DNS/NTP exceptions do not
implicitly grant hairpin access.

There are no `he_ipv6.port_forwards` or `he_ipv6.hairpin` inputs. Each
public destination needs its declared listener bound to its ULA address or
an appropriate IPv6 wildcard. Explicit-connection-only clients receive
IPv6 networking and exact VIP/port exceptions without general internet
access or public listeners. Direct ULA access is not added.

For TCP or UDP source A, target B and port P, requests start as
`A_ULA:client_port -> VIP:P`. Routed DNAT and SNAT deliver
`B_gateway:translated_port -> B_ULA:P`; replies reach A as
`VIP:P -> A_ULA:client_port`. The kernel may translate source ports so
concurrent clients can reuse the same original port. This also applies when
A equals B. Applications see the target gateway as the hairpin source;
external HE clients retain their actual IPv6 source.

Only exact assigned managed-guest ULA sources are eligible. LAN/VPN client
prefixes, host-originated requests, IPv4 hairpin and direct ULA dependencies
remain outside this feature. VPN clients must reach the VIP bearing their
gateway guest's assigned ULA; VPN routing/translation is operator-owned.
Local Pi-hole records remain IPv4-only. Use an explicit VIP connection or
a deliberate client-side resolution override for testing.

For an existing HE deployment, remove the two old maps from the shared
file and review both root plans. Home now exposes every declared public
port and derives hairpin from effective egress or explicit connections;
previous manual forward omissions no longer restrict public ingress. Host-config consumes the tunnel settings only.
Keep stopped-first provisioning for new guests and verify the ULA address,
gateway and route inside existing guest OSes: a cloud-init plan alone does
not prove the address is active.

Inspect `ipv6_port_forwards` for generated keys such as `tcp-443` and
`udp-53`. Inspect `ipv6_hairpin` for keys such as `cloud/udp-53`.
Each hairpin value gives source guest/address/VNet, forward key, public
address, protocol and port, target guest/address/VNet, and
`translated_source_address` (the target gateway). Outputs are empty when
HE is off or no forwards exist. They describe desired state, not health.

Remove or move a guest's `public_ports` entry to withdraw its public forward
and corresponding hairpin access. Removing the final public port removes
hairpin-only IPv6 participation; independent egress remains. TCP and UDP
revocation are separate even when they share a port number. The helper
withdraws affected authorization before purging exact zone-0 and zone-1
connection views. A private `hairpin-pending` journal records protocol and
original/translated port snapshots before deletion so retries can finish
after routed evidence is gone. Existing TCP manifests and pending journals
remain readable.

On failure, retain the blocking guard and recovery files, repair the
reported problem and reconcile/retry through the existing helper lifecycle.
Do not delete the journal or flush global conntrack. Full feature disable
still follows home before host-config as described below.

## Prerequisites and ownership

On Proxmox, have `ip`, `sysctl`, `nft`, `conntrack`, `ip6tables-save`, POSIX
shell and the existing `pve-firewall` backend available. Install missing
`nftables`/`conntrack` packages through your normal host-management process.
HSP uses separate native nftables tables alongside `pve-firewall`; it does
not switch to the `proxmox-firewall` backend or replace global firewall
configuration. Routed IPv6 NAT uses conntrack zone 0. Only the exact
`fwbr<VMID>i0` bridges of participating guests use zone 1 before tracking;
this prevents an earlier bridge traversal from committing an untranslated
NAT binding before routing through `hsp-he6`. Foreign IPv6 zone/NAT ownership
is rejected by preflight. Existing IPv4 zone/NAT rules remain unchanged.

On first adoption, this correction briefly blocks forwarding and clears
affected IPv6 connections, including old untranslated bindings. Later
bridge changes migrate only the affected guests; unchanged guests retain
their sessions. Permission revocation/removal cleans the configured tuples
in both contexts, without flushing other guests or host traffic.

Both roots need SSH-agent access to the same Proxmox node. In home, set the
existing `proxmox_ssh` object; non-root users need passwordless sudo. Its
optional `port`/`host_key` fields also apply to the ingress connection.
Retain SSH settings until an existing deployment is fully removed.
Fresh off configurations do not need or connect over SSH for this feature.

Host-config owns `hsp-he6`, `hsp-vip6`, the routes, forwarding sysctl, and
`ip6 hsp_he_host` INPUT protection. It installs the input guard before
exposing the public address. Home owns per-guest IPv6 SDN/initialization/
firewall policy plus `ip6 hsp_he_ingress` DNAT, SNAT and forwarding guards.
Helpers track ownership and refuse name collisions. Native SDN subnet
`snat` stays false for IPv6; explicit SNAT is in the edge table.

When `manage_host_firewall = false`, HSP does not take ownership of the node's
Proxmox rule list. Inspect `ipv6_host_requirements` and permit the equivalent
protocol-41/NDP/ICMPv6 traffic in your existing policy. The independent HSP
input/forwarding guards still restrict this feature; their accepts cannot
override a drop in another firewall chain. With node ownership enabled,
only the required transport/control exceptions are added to the existing
single node-rules resource. IPv6 host GUI/SSH remains closed.

## Ordered cutover

Run these commands from your copied starter directory, with the shared JSON
settings configured and credentials loaded.

Review both saved plans while the old tunnel is still available:

```sh
terraform -chdir=host-config init
terraform -chdir=home init
terraform -chdir=host-config plan -out=hosts.tfplan
terraform -chdir=home plan -parallelism=1 -out=home.tfplan
```

Manually stop the old HE endpoint BEFORE applying the enabled host plan.
Expect an IPv6 cutover outage. Then apply host-config followed by home:

```sh
terraform -chdir=host-config apply hosts.tfplan
terraform -chdir=home apply -parallelism=1 home.tfplan
terraform -chdir=host-config output he_ipv6_status
terraform -chdir=home output ipv6_networks
terraform -chdir=home output ipv6_port_forwards
terraform -chdir=home output ipv6_egress
terraform -chdir=home output ipv6_hairpin
terraform -chdir=home output ipv6_host_requirements
```

Check actual guest OS addresses/routes and listeners. VM cloud-init changes
do not guarantee a running guest immediately changes its network; perform
any needed guest reconfiguration/restart deliberately. Keep the existing
stopped-first activation workflow for new guests. Terraform does not restart
guests or networking, and IPv4 guest startup is not gated on HE availability.

Manually move the EdgeRouter protocol-41 DNAT target to `192.0.2.10`,
restricted to HE server `203.0.113.1`; ensure the return IPv4 encapsulation
uses the registered public IPv4. This is IP protocol 41, not TCP/UDP port 41.
No IPv6 address or route on the physical LAN/EdgeRouter is required for this
Proxmox-terminated design. Do not run both HE endpoints intentionally.

The default tunnel MTU is 1480 for a 1500-byte IPv4 path. Confirm your path
and HE MTU settings, lower the configured value if required (minimum 1280),
and verify PMTU/large transfers. HSP keeps the shared zone/NIC MTU unchanged.

## Applications and public DNS

Proxy and mail listeners must bind to their ULA address (or appropriate
IPv6 wildcard) and use the configured ULA gateway for replies. HTTPS still
terminates at `proxy-public`; ordinary HTTP backend connections can remain
IPv4. Mail TCP forwards retain backend TLS/STARTTLS and the real external
IPv6 client address; no TCP proxy or PROXY protocol is needed.

HE filters TCP 25 by default; arrange its removal before relying on SMTP.
Outgoing IPv6 mail works when effective egress permits the destination port
and HE allows it. All egress guests share the public source IPv6; reverse
DNS, SPF and application/delivery configuration remain your responsibility.
See [HE's FAQ](https://ipv6.he.net/certification/faq.php).

After external acceptance, publish public authoritative records, for example:

```dns
mail.example.com. AAAA 2001:db8:2::2
www.example.com.  AAAA 2001:db8:2::2
example.com.     MX 10 mail.example.com.
```

Existing A records stay. Local Pi-hole DNS remains IPv4-only, and HE's
optional resolvers are not configured automatically. Hairpin is available to
authorized managed guests; IPv6 LAN/VPN client-prefix hairpin remains
outside this feature. IPv4-only LAN clients keep using A records and their
existing routes.

## Live acceptance

These are operator checks after manual cutover, not outcomes proven by
Terraform mocks or the fake-command tests. **Managed hairpin Linux live
acceptance remains pending.** Collect command output, compiled Proxmox
rules, counters, application logs and synchronized captures on the source/target
VNets, exact firewall bridges and `hsp-he6` for the matrix below:

| Check | Expected result |
| --- | --- |
| `systemctl status hsp-he-ipv6 hsp-ipv6-ingress`; `ip -d tunnel show hsp-he6`; `ip -6 addr`; `ip -6 route show table all` | Owned tunnel/VIP, per-slot ULA routes, reserved blackhole/default routes; no changes to IPv4. UP alone does not prove HE connectivity. |
| `nft list table ip6 hsp_he_host`; `nft list table ip6 hsp_he_ingress`; `ip6tables-save`; `conntrack -L -f ipv6 -o extended` | Correct syntax/compiled rules, counters, and zone 0 on the routed/NAT hop and zone 1 on exact owned legacy firewall bridges, in both directions. The router guard skips intermediate `fwbr*` legs; native guest filtering still applies there and the routed hop must hit the guard. |
| External `curl -6 --resolve 'mail.example.com:443:[2001:db8:2::2]' https://mail.example.com/` | Correct GUI through the proxy before public DNS publication. |
| Ready SMTP/submission/IMAP with TLS/STARTTLS | Correct mail guest; application logs contain the original external IPv6 client. |
| Egress-only guest: allowed TCP/UDP and `ping -6` with configured ICMP | Connections/replies work; remote service sees the shared public VIP. Unlisted ports remain denied. |
| Large transfers/PMTU and related ICMPv6, including errors sourced from the tunnel-link prefix | No size-dependent stalls; related errors are accepted only for currently authorized NAT flows. |
| Host listeners on public VIP, tunnel address and ULA gateways; unmapped public ports | GUI/SSH and other undeclared listeners unreachable, including with node firewall ownership off or no public forwards. |
| Guest-to-guest/host/protected destinations, forged global/ULA/link-local/unspecified sources, RA/redirect attempts | Application initiation/spoofing denied; only scoped NDP/DAD and required errors work. |
| Remove an active forward or TCP/UDP/ICMP egress grant | Only affected flows stop and cannot reconnect; unchanged other guests/protocols/inherited grants remain usable. |
| Cleanup failure, firewall reload, guest/host reboot, and final off state | Failure retains a blocking guard; owned services reconcile after reboot; removal leaves IPv4 usable. |

For hairpin acceptance, first inspect compiled `pve-firewall` rules to
confirm native hairpin exceptions precede protected-range drops and exact
source/MAC filters remain active. Choose existing TCP and UDP forwards, two
managed clients and an unmanaged source. Include both VM and LXC sources
and targets. Retain unrelated external, internet and other-client sessions
through reduction and reload checks.

| Hairpin check | Required evidence / expected result |
| --- | --- |
| VM-to-LXC, LXC-to-VM and self-hairpin to `VIP:P` | Each declared TCP/UDP service is reachable; backend logs/capture show target gateway as source and client capture shows replies from `VIP:P`. No corresponding application packets appear on `hsp-he6`. |
| Two clients bind the same fixed TCP or UDP source port concurrently, plus self-hairpin | All connections coexist; correlate each original source tuple with its translated tuple, including translated-port collisions resolved by the kernel. |
| Exact conntrack views during each connection | `conntrack -L -f ipv6 -o extended` (select zones explicitly as needed) shows zone 0 original `SOURCE:client_port -> VIP:P`, reply `TARGET:P -> GATEWAY:translated_port`; zone 1 source-side `SOURCE:client_port -> VIP:P` and target-side `GATEWAY:translated_port -> TARGET:P`, with their replies. Match endpoint/port tuples to captures, including self-hairpin. |
| Same port number served over TCP and UDP by different guests | Each protocol reaches its declared guest; removing UDP preserves active TCP sessions and vice versa. |
| Large transfers and related ICMPv6 errors from an intermediate router | No size-dependent stalls; authorized master tuples admit related errors even when the router is not either application endpoint. Unrelated errors/new ICMP gain no hairpin permission. |
| Unauthorized managed or unmanaged client, undeclared VIP port, direct target ULA, forged source, LAN/VPN-prefix source, and host GUI/SSH | All application attempts denied, including unmapped VIP ports and management via gateway addresses. Existing scoped NDP/DAD remains usable. |
| Remove a public port, remap its owner, then remove independent E on the same port | Affected sessions stop and cannot reconnect; removing a public port retains E and other protocol/port sessions; removing matching egress also revokes hairpin unless an explicit connection still authorizes it. Removing a connection retains hairpin if matching egress remains. Capture both bridge views to confirm exact cleanup. |
| No-op service reload, firewall reload, additions and guest/host reboot | Reloads/additions preserve unrelated sessions; after reboot new authorized connections work and denied connections remain denied (host reboot destroys existing kernel sessions). |
| Controlled cleanup failure and retry, including after zone-0 deletion | Blocking guard remains on failure; retained journal permits complete retry without broad target-port deletion or resetting other clients. Perform only in an operator-controlled test environment. |
| External HE ingress plus baseline internet TCP/UDP/ICMP | External applications still see real client IPv6; permitted egress works with public-VIP SNAT and unlisted ports remain denied. IPv4 and local DNS behavior remain unchanged. |

Before activation, syntax-check the staged rules transaction on Linux with
`nft -c -f /etc/hsp-ipv6-ingress/rules.nft` on a disposable copy/
namespace without an existing table of the same name. Inspect the actual
loaded tables after service activation. A standalone rules file is not a
safe replacement transaction for an already-loaded table; the helper
validates and atomically replaces its own table during normal operation.

## Disable and rollback

Withdraw public AAAA records and respect their TTLs, then set the SAME
`he_ipv6.enabled = false`. Plan/apply **home first**, using the shared file,
then host-config. Home blocks the feature, purges owned DNAT/SNAT conntrack
entries, restores guest IPv6 denial and removes ULA subnets; host-config
then withdraws the public address/tunnel/routes before removing its input
guard. Retain SSH settings throughout. Finally remove the manual router
forward. No global firewall/conntrack flush or IPv4 guest removal occurs.

Helpers return an error and retain a blocking guard if connection cleanup
fails. A failed permission reduction also installs that guard if preflight
or rule replacement fails; an unsuccessful addition keeps the previous
restrictive policy. Repair the reported problem and reconcile before treating
removal as complete. Two destroy-only SSH agent gates explicitly retry helper
cleanup even when systemd has marked a failed stop inactive; Terraform keeps
the helper/unit resources until the gate succeeds. They retain SSH connection
metadata in state, with no new private keys or passwords. If nft itself cannot
install the guard, withdraw the HE transport manually before retrying. Forwarding sysctl runtime state is left enabled because other
networking may depend on it; only HSP's persistent sysctl file is removed.

Use the full disable/reconfigure/enable cycle for routed/ULA prefix or
participating guest-slot changes. A two-root edit/apply is not atomic. To
restore the former endpoint, stop/remove this endpoint first, then manually
restore the old NAT target/startup. The implementation never accesses it.

## Native ICMP rule display

Portless outbound ICMPv6 rules use the UI's canonical `ipv6-icmp` name.
The pinned BPG provider does not expose the separate `icmp-type` field,
so typed NDP/error/control rules retain the legacy `icmpv6` plus numeric
`dport` encoding supported by `pve-firewall`. The Proxmox editor can mark
that alias invalid and show a blank ICMP-type field even when the rule
compiles. Do not simply rename those typed rules: the legacy numeric type
encoding depends on the `icmpv6` spelling. Native firewall ownership is
retained; this configuration adds no Perl policy helper or security groups.

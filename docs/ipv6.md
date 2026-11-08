# Optional HE IPv6: public ports, internet egress and managed hairpin

HSP can terminate a Hurricane Electric (HE) 6in4 tunnel on Proxmox. It uses
one public IPv6 address for TCP port forwards and permitted guest internet
traffic. The feature defaults off. IPv4-only deployments need no new values.

Incoming TCP ports are destination-NATed to individual guests. Outgoing
TCP/UDP/ICMP is allowed by the existing effective `internet_egress_ports`
list and source-NATed to the shared public address. Incoming clients retain
their real IPv6 source address. Explicitly granted managed guests can also
reach the public TCP forwards locally, including their own service. These
hairpin requests use the target ULA gateway as their source. Guest VNets
remain separate; this does not grant direct ULA access.

## Addressing and configuration

The tunnel's link /64 connects Proxmox to HE; the routed /64 supplies the
public service address. The host owns offset 2 of the routed prefix as a
/128 on `hsp-vip6`. The remaining public prefix is blackholed. Guest
addresses come from a separate, stable ULA /48, with one /64 per slot and
gateway/guest offsets 1/2. A routed /48 from HE is unnecessary.

For the deployment discussed in the design:

| Purpose | Value |
| --- | --- |
| HE server IPv4 | `216.66.84.46` |
| Router public IPv4 registered with HE | `178.226.181.114` |
| Proxmox LAN/local tunnel IPv4 | `192.168.100.10` |
| HE server/client tunnel IPv6 | `2001:470:1f14:4d4::1` / `2001:470:1f14:4d4::2/64` |
| Routed service prefix | `2001:470:1f15:4d6::/64` |
| Shared public service address | `2001:470:1f15:4d6::2` |
| Illustrative private aggregate | `fd42:77:1::/48` |
| Proxy in slot 2: gateway / guest | `fd42:77:1:2::1` / `fd42:77:1:2::2` |

Choose a unique ULA /48 for your site and keep it stable. Public addresses
are never assigned to guest VNets. The Proxmox HE default route is host-wide;
host-originated IPv6 may also use it, subject to host filtering.

Copy [the shared example](../environments/he-ipv6.tfvars.example) to
`environments/he-ipv6.tfvars` (already Git-ignored). Fill in your allocation
and change `enabled` to true only for the planned cutover:

```hcl
he_ipv6 = {
  enabled       = true
  server_ipv4   = "216.66.84.46"
  local_ipv4    = "192.168.100.10"
  client_ipv6   = "2001:470:1f14:4d4::2/64"
  server_ipv6   = "2001:470:1f14:4d4::1"
  routed_prefix = "2001:470:1f15:4d6::/64"
  ula_prefix    = "fd42:77:1::/48"
  mtu           = 1480
  protected_cidrs = [] # Add any real protected IPv6 LAN/VPN networks.
  port_forwards = {
    http  = { guest = "proxy-public", port = 80 }
    https = { guest = "proxy-public", port = 443 }
  }
  hairpin = {} # Optional managed-guest grants are separate from internet egress.
}
```

Use the SAME shared file for both Terraform roots. Neither root reads the
other's state. Forgetting the file selects the off default and can plan
removal of an existing HE deployment; review the saved plans.

Forwarded ports must be unique, TCP, and already listed in the target's
`public_ports`. Ports 22/8006 remain forbidden. UDP public forwarding and
port-number translation are outside this interface. Add a mail forward
only after declaring the guest, configuring its listeners and explicitly
listing its ports, for example `smtp = { guest = "mail", port = 25 }`.
No mail guest or mail software is automatically installed.

Guests receive ULA addresses when they have a forward, a nonempty
effective internet-egress list, OR an explicit hairpin source grant. Global,
per-guest and role defaults are combined exactly as for IPv4; monitoring inherits TCP 80/443. Thus global
UDP 123 gives **every guest** IPv6 when HE is enabled. A guest's empty local
list still inherits global/role permissions. Egress-only guests need no
`public_ports` and receive no incoming listener allowance.

`{ protocol = "icmp" }` remains portless and also permits internet ICMPv6,
including outgoing ping, after protected-network and router-control drops.
Required NDP/DAD and ICMPv6 error messages work independently. There is no
separate IPv6-egress flag. Fixed DNS/NTP infrastructure exceptions remain
IPv4; local Pi-hole records remain IPv4-only. Public DNS queries over IPv4
can still return AAAA answers for internet destinations.

## Managed-guest hairpin grants

The default `hairpin = {}` grants no local access to the public VIP. Inside
`he_ipv6`, opt in existing source guests to existing `port_forwards` keys:

```hcl
hairpin = {
  monitoring   = ["https"]
  proxy-public = ["https"] # The target can call its own public service.
}
```

Each set must be nonempty. Grants name forward keys, not destination guest
names or arbitrary ports. Targets still need the declared TCP `public_ports`
entry and a working listener on their ULA address or IPv6 wildcard. Roles
never generate hairpin grants. An explicit grant is an operator-authorized
exception to protected-destination denial, including for restrictive VPN
roles, limited to that VIP and TCP port.

Internet egress (E) and hairpin (P) are independent permissions: TCP443
internet access does not grant VIP TCP443, and a hairpin grant adds no
internet access. A hairpin-only VM/LXC receives its slot ULA /64, gateway
and native firewall policy, without a public listener or internet allowance.
Removing its last grant removes IPv6 participation only if no forwarding or
effective-egress reason remains; IPv4 identity is preserved.

For source A, target B and port P, requests start as
`A_ULA:client_port -> VIP:P`. Routed DNAT and SNAT deliver `B_gateway:translated_port -> B_ULA:P`;
replies reach A as `VIP:P -> A_ULA:client_port`. The kernel may translate
source ports so concurrent clients can reuse the same original port. This
also applies when A equals B. Applications log the gateway identity for
hairpin clients; external HE clients retain their actual IPv6 source.

Only exact assigned managed-guest ULA sources are eligible. LAN/VPN client
prefixes, host-originated requests, IPv4 hairpin, UDP forwarding and direct
ULA dependencies remain outside this feature. A VPN gateway guest can be
granted access, but its clients must reach the VIP bearing that guest's
exact assigned ULA; VPN routing/translation is operator-owned. No DNS
changes are made: local Pi-hole records remain IPv4-only. Use an explicit
VIP connection or a deliberate client-side resolution override for testing.

On an already enabled HE deployment, pass the same shared file to both
roots and review both plans. Adding grants changes home; host-config
accepts the field but should show no networking delta. Apply the reviewed
home plan deliberately. Keep stopped-first provisioning for new guests and
verify the ULA address, gateway and route inside an existing guest OS before
testing: a cloud-init plan alone does not prove the address is active.

Inspect `terraform -chdir=environments/home output ipv6_hairpin` for desired
grants keyed by `source_guest/forward_key`. Each value gives source guest,
address and VNet, forward key, public address, TCP protocol/port, target
guest, address and VNet, and `translated_source_address` (target gateway).
It is `{}` when off or unconfigured. This output describes desired state,
not service health or proof of successful Linux packet traversal.

Remove a grant from the shared map and apply the reviewed home plan with
SSH retained until cleanup succeeds. Removing P must preserve independent
E and other clients' P sessions, even on the same port; removing E must
preserve independent P. The helper withdraws affected authorization before
purging exact zone-0 and both zone-1 views. Its private runtime
`hairpin-pending` journal persists original/translated port snapshots before
deletion, so retry can finish target-side cleanup after zone 0 is gone.
On failure, retain the blocking guard and recovery files, repair the
reported problem and reconcile/retry through the existing helper lifecycle.
Do not delete the journal, flush conntrack globally or treat a failed stop
as completed removal. Full feature disable still follows home before
host-config as described below.

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

Review both saved plans while the old tunnel is still available:

```sh
terraform -chdir=environments/host-config init
terraform -chdir=environments/home init
terraform -chdir=environments/host-config plan -var-file=hosts.tfvars -var-file=../he-ipv6.tfvars -out=hosts.tfplan
terraform -chdir=environments/home plan -var-file=home.tfvars -var-file=../he-ipv6.tfvars -parallelism=1 -out=home.tfplan
```

Manually stop the old HE endpoint BEFORE applying the enabled host plan.
Expect an IPv6 cutover outage. Then apply host-config followed by home:

```sh
terraform -chdir=environments/host-config apply hosts.tfplan
terraform -chdir=environments/home apply -parallelism=1 home.tfplan
terraform -chdir=environments/host-config output he_ipv6_status
terraform -chdir=environments/home output ipv6_networks
terraform -chdir=environments/home output ipv6_port_forwards
terraform -chdir=environments/home output ipv6_egress
terraform -chdir=environments/home output ipv6_hairpin
terraform -chdir=environments/home output ipv6_host_requirements
```

Check actual guest OS addresses/routes and listeners. VM cloud-init changes
do not guarantee a running guest immediately changes its network; perform
any needed guest reconfiguration/restart deliberately. Keep the existing
stopped-first activation workflow for new guests. Terraform does not restart
guests or networking, and IPv4 guest startup is not gated on HE availability.

Manually move the EdgeRouter protocol-41 DNAT target to `192.168.100.10`,
restricted to HE server `216.66.84.46`; ensure the return IPv4 encapsulation
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
mail.example.com. AAAA 2001:470:1f15:4d6::2
www.example.com.  AAAA 2001:470:1f15:4d6::2
example.com.     MX 10 mail.example.com.
```

Existing A records stay. Local Pi-hole DNS remains IPv4-only, and HE's
optional resolvers are not configured automatically. Hairpin is limited to
explicitly granted managed guests; IPv6 LAN/VPN client-prefix hairpin remains
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
| External `curl -6 --resolve 'mail.example.com:443:[2001:470:1f15:4d6::2]' https://mail.example.com/` | Correct GUI through the proxy before public DNS publication. |
| Ready SMTP/submission/IMAP with TLS/STARTTLS | Correct mail guest; application logs contain the original external IPv6 client. |
| Egress-only guest: allowed TCP/UDP and `ping -6` with configured ICMP | Connections/replies work; remote service sees the shared public VIP. Unlisted ports remain denied. |
| Large transfers/PMTU and related ICMPv6, including errors sourced from the tunnel-link prefix | No size-dependent stalls; related errors are accepted only for currently authorized NAT flows. |
| Host listeners on public VIP, tunnel address and ULA gateways; unmapped public ports | GUI/SSH and other undeclared listeners unreachable, including with node firewall ownership off or no public forwards. |
| Guest-to-guest/host/protected destinations, forged global/ULA/link-local/unspecified sources, RA/redirect attempts | Application initiation/spoofing denied; only scoped NDP/DAD and required errors work. |
| Remove an active forward or TCP/UDP/ICMP egress grant | Only affected flows stop and cannot reconnect; unchanged other guests/protocols/inherited grants remain usable. |
| Cleanup failure, firewall reload, guest/host reboot, and final off state | Failure retains a blocking guard; owned services reconcile after reboot; removal leaves IPv4 usable. |

For hairpin acceptance, first inspect compiled `pve-firewall` rules to
confirm native hairpin exceptions precede protected-range drops and exact
source/MAC filters remain active. Choose an existing TCP forward, two explicitly
granted clients and an ungranted client. Include both VM and LXC sources
and targets. Retain unrelated external, internet and other-client sessions
through reduction and reload checks.

| Hairpin check | Required evidence / expected result |
| --- | --- |
| VM-to-LXC, LXC-to-VM and self-hairpin to `VIP:P` | Each granted connection succeeds; backend logs/capture show target gateway as source and client capture shows replies from `VIP:P`. No corresponding application packets appear on `hsp-he6`. |
| Two clients bind the same fixed TCP source port concurrently, plus self-hairpin | All connections coexist; correlate each original source tuple with its translated tuple, including translated-port collisions resolved by the kernel. |
| Exact conntrack views during each connection | `conntrack -L -f ipv6 -o extended` (select zones explicitly as needed) shows zone 0 original `SOURCE:client_port -> VIP:P`, reply `TARGET:P -> GATEWAY:translated_port`; zone 1 source-side `SOURCE:client_port -> VIP:P` and target-side `GATEWAY:translated_port -> TARGET:P`, with their replies. Match endpoint/port tuples to captures, including self-hairpin. |
| Large transfers and related ICMPv6 errors from an intermediate router | No size-dependent stalls; authorized master tuples admit related errors even when the router is not either application endpoint. Unrelated errors/new ICMP gain no hairpin permission. |
| Ungranted client, ungranted VIP port, direct target ULA, forged source, LAN/VPN-prefix source, and host GUI/SSH | All application attempts denied, including unmapped VIP ports and management via gateway addresses. Existing scoped NDP/DAD remains usable. |
| Revoke active P, remap its forward, then revoke independent E on the same port | Affected sessions stop and cannot reconnect; revoking P retains E, external ingress and other-client/self sessions; revoking E retains P and unrelated TCP/UDP/ICMP sessions. Capture both bridge views to confirm exact cleanup. |
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

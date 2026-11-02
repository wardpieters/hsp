# Self-hosting infrastructure design

Date: 2026-10-28  
Status: Approved and implemented on 2026-10-28; simplified to Terraform resources/commands and explicit API-managed DNS at the user's request on 2026-10-29. A wildcard is no longer required. Live deployment and acceptance remain pending.

## Intent and confirmed constraints

Build a reproducible foundation for securely hosting services on the existing single Proxmox VE 9.x node. Terraform should create guests, their networks and firewall policies, and their Pi-hole DNS records together. Pi-hole is installed directly on a VM or physical host and is reported as version 6.6.1; its exact component/API versions will be recorded during deployment preflight.

The user requires isolation between guests, restricted access to the home LAN, administrative access through a VPN or management VM, and a separate access policy for family and friends using services such as ownCloud. Some services are public through EdgeRouter X port forwards.

**No VLAN configuration on the EdgeRouter.** Proxmox owns the internal networks and routing. The selected external integration is a static route on the EdgeRouter via Proxmox's existing LAN address, followed by port forwards targeting guest addresses directly. Terraform will produce the necessary route and port-forward inventory; it will not manage the router itself.

At design time the workspace was an empty directory, not an initialized Git repository. After approval, the implementation was committed on the local `feat/self-hosting-infrastructure` branch.

## Goals, non-goals, and failure conditions

Goals:

- Stable, explicitly assigned IPv4 addresses and predictable guest identifiers.
- Separate virtual networks per VM, with required connections described as firewall rules.
- Deny connections between unrelated guests, into host management, and into the home LAN.
- Add, update, and remove platform DNS records with the corresponding guest declaration.
- Permit each DNS name to resolve to a selected reverse proxy address or the guest address.
- Support future admin VPN, service VPN, reverse proxy, and container-host VMs without changing the physical network design.
- Document bootstrap, import, verification, recovery, and normal provisioning.

Initial implementation does not deploy application stacks, configure public DNS or certificates, configure the reverse proxy software, enroll VPN clients, replace Pi-hole, migrate existing services automatically, or create a multi-node cluster. Those services must be configured before their access paths can pass live acceptance tests; infrastructure readiness alone is not a working VPN or application deployment.

Failure conditions include relying on NAT for isolation, exposing a new guest before its firewall exists, enabling an experimental firewall backend as an unnoticed prerequisite, allowing family VPN users administrative access, removing unrelated DNS records, or changing existing host networking without an explicit migration plan.

## Approaches considered

| Approach | Benefits | Costs and outcome |
| --- | --- | --- |
| Shared application subnet with per-guest Proxmox firewall rules | Few networks; selective guest connections stay local | Viable, but shares a Layer 2 segment. Not the proposed default given the isolation requirement. |
| Internal Proxmox Simple SDN VNets, with a subnet per guest | Separates guest broadcast domains; Proxmox routes required traffic locally; no physical VLANs | More SDN objects, but Terraform can generate them. Selected topology; the per-guest granularity is the assistant's proposed default for approval. |
| VLANs routed by the EdgeRouter | Central router enforcement | Explicitly ruled out by the user. |

A dedicated firewall VM remains an alternative if a future requirement needs a full routing appliance. It is not required for this design and would add bootstrap and availability dependencies.

## Internal networks and addresses

Use one Simple SDN zone restricted to the existing node. Each guest receives its own VNet and IPv4 subnet. Do not use VLAN, VXLAN, EVPN, BGP, or a physical bridge attachment for these internal VNets.

Proposed addressing convention, to be confirmed against the real networks before applying:

- One private aggregate supplied as `platform_cidr`; no live range is assumed by this document.
- A fixed-size `/30` per guest, with gateway at offset 1 and guest at offset 2.
- An explicit, unique subnet slot per guest; never derive slots from list position or sorted names.
- Stable, unique VM IDs and VNet identifiers; validate Proxmox naming limits.

For example only, an unused `/24` could hold 64 `/30` guest networks. The implementation may accept a larger aggregate after checking LAN, existing guest, VPN, and remote-site overlaps. Deleting or inserting a guest must not renumber other guests.

The subnet needs addresses for both the Proxmox gateway and the VM. A `/30` has exactly two conventionally usable addresses and replaces the unnecessarily generous `/29` in the first draft. A guest `/32` is possible in a different host-routing design, with explicit gateway reachability and corresponding host routes, but is not a drop-in subnet containing both endpoints. A `/31` can hold two endpoints under point-to-point semantics; it is not the default without checking support across SDN, the selected guest image, and its network renderer. The guest still receives only one address, and its anti-spoofing allowlist remains restricted to that single `/32` regardless of subnet size.

In a Simple zone, Proxmox receives each configured gateway address, creating the connected routes between guest networks. Enable forwarding persistently. A separate network prevents direct Layer 2 guest communication; guest firewall policies must still block undesired routed traffic.

Install a persistent blackhole/reject route for the aggregate on Proxmox, with the more-specific connected subnet routes taking precedence. This prevents packets for unused slots looping between the EdgeRouter's aggregate route and Proxmox's default route. Treat host route persistence as a bounded bootstrap requirement; do not claim the SDN subnet resource manages it.

Enable SDN SNAT for guest-initiated outbound connections through the existing LAN uplink. Test its interaction with inbound router DNAT, including the preserved external client address and symmetric replies. Do not add an unnecessary second inbound port forward on Proxmox.

## External routing and the home LAN

The EdgeRouter configuration consists of:

1. A route for `platform_cidr` using the existing Proxmox LAN IP as next hop.
2. Explicit public port forwards targeting the relevant guest IP and service port.
3. Existing WAN firewall and outbound NAT behavior, checked for this traffic path.

These are documented operator changes, not resources managed by an EdgeOS Terraform provider. Adding an ordinary guest requires no router change. Publishing a new internet-facing port still requires a port-forward change.

The static route provides reachability, not permission. Guest ingress rules reject home-LAN sources before public-service allow rules. Guest egress rules reject protected destinations except narrowly declared infrastructure dependencies. Source addresses alone do not prove that a request entered through the internet-facing interface; do not label a broad public allow rule as authenticated WAN provenance.

The physical uplink and existing host management interface stay on the current LAN. Software firewall policy constrains their access; this design does not claim physical separation from a hostile LAN segment. Preserve a specific temporary administrator source during migration, then remove that exception after admin VPN access is verified. Console access remains the recovery path.

## Firewall enforcement

Use Proxmox's established per-guest firewall facilities with firewall enforcement enabled at the required datacenter, guest, and NIC levels. Prefer the existing supported backend; the design must not depend on VNet/FORWARD rules that the stock backend ignores. Record the installed backend and verify its effective behavior before enabling workloads.

For each guest:

- Default incoming and outgoing policy is DROP.
- Enable MAC filtering and populate the interface's `ipfilter-net0` set with the assigned IPv4 address. Do not assume a VM's cloud-init address automatically becomes an anti-spoofing rule.
- Allow declared dependencies by destination and protocol/port; allow return traffic through state tracking.
- Block other platform guests, home networks, VPN networks, and host management unless a specific exception precedes the block.
- Allow internet egress only on each guest's explicit `internet_egress_ports` TCP/UDP destination ports, after protected-range blocks. The default empty list grants no general internet egress. Approved DNS over TCP/UDP 53 and approved NTP over UDP 123 remain separate infrastructure exceptions.
- Public ingress allows declared ports only after protected-source exclusions. SSH is never added by marking an application public.

DNS to an existing Pi-hole on the LAN is a narrow infrastructure exception, not permission to reach its admin UI or other LAN services. Include every host gateway address and the host's management address in host protection; Proxmox services may listen on internal gateway addresses too.

Host firewall policy denies management access from guest networks by default and allows only the admin access gateway and the temporary bootstrap administrator source as appropriate. Audit Proxmox's default management exceptions; do not assume DROP removes the built-in local-network allowances.

The assistant's initial scope choice is IPv4 service addressing. Do not route global IPv6 into guests or enable SLAAC for application connectivity. Enforce and test IPv6 restrictions as well, including host access over link-local addresses. Any required neighbor-discovery traffic must not become permission to use application or management ports.

## Admin and family access

Declare separate roles for ordinary workloads, reverse proxies, admin VPN gateways, and service VPN gateways. These roles select narrow policy profiles; they do not grant a whole network unrestricted access.

- An admin VPN gateway may reach specified Proxmox management ports and configured guest administration ports.
- A service VPN gateway may reach the selected private reverse proxy over HTTPS and an approved DNS resolver. It cannot reach guest administration ports, host management, or the home LAN.
- Reverse proxies may reach explicitly declared backend guest ports.
- Ordinary application VMs cannot initiate connections to the VPN gateways or other guests without an explicit dependency.

For the first implementation, admin and service VPNs are separate gateway VMs with separate guest IPs. This is the assistant's proposed default, so hypervisor policy can distinguish their privileges. Future VPN software may SNAT clients to the appropriate gateway IP to avoid extra host routes for VPN client networks. Client authentication, peer isolation, and role assignment must then be enforced on those gateways; clients cannot self-select an administrative identity.

The guest module provisions these VMs and network policies; installing/configuring the VPN service is a follow-up deliverable. A management VM is optional behind the admin gateway.

If public and VPN-only applications coexist, use distinct public and private proxy endpoints; separate proxy VMs are the proposed default. A single shared HTTPS listener requires correctly enforced application/proxy access policy for each hostname. A Proxmox rule allowing TCP 443 cannot distinguish hostnames. Endpoint address and backend rules remain configurable, so this does not force migration of the existing proxy in the initial apply.

## Terraform boundaries and lifecycle

Proposed modules:

- `platform_network`: Simple zone and shared policy data; outputs the router route inventory.
- `guest_network`: a stable VNet and `/30` subnet for a fixed slot.
- `vm`: a VM from an explicitly selected cloud-init-compatible template, static network configuration, SSH public keys, guest firewall options, anti-spoofing set, and ordered rules.
- `dns_records`: explicit Pi-hole records, with `direct`, `proxy`, or `none` routing per name and an explicit proxy target when applicable.
- `proxmox_host`: persistent IPv4 forwarding, aggregate termination, and guest startup ordering through native Terraform file/service resources.
- `service_vm`: composition of guest network, VM, and optional DNS, exposing one declaration to an operator. Lower-level modules remain reusable.

Use stable map keys and explicit identifiers. Keep address allocation authoritative in Terraform; do not introduce a second dynamic allocator or DHCP for these static guests. SDN IPAM metadata and cloud-init must not disagree; the builder may omit optional IPAM registrations where native provider support is insufficient.

Pin tested versions of `bpg/proxmox`, a Pi-hole v6 provider, and a remote-file provider for the small host configuration boundary, and commit the provider lock file. `neuspaces/system` is a candidate for remote-file lifecycle over SSH; validate its behavior before selecting it. Select the supported VM resource rather than an experimental VM rewrite. Use the provider's documented SDN apply/finalization mechanism, including deletion handling, and verify a second plan is empty. Do not silently install prerelease builds.

Use native provider resources for guest, SDN, firewall, and DNS lifecycle. If persistent forwarding/aggregate routing needs host access, isolate it into a small, idempotent bootstrap procedure with a clear read-back check. Do not scatter SSH provisioners through guest modules or add unmanaged host DNAT.

New guests default to stopped, with autostart disabled. Inspect their NIC/guest firewall flags, address filters, and effective policy before setting `started = true` in a second Terraform apply. Following the user's Terraform-only correction, this is a documented operator step rather than a custom automated activation guard. Terraform's sibling-resource ordering does not guarantee that a newly created running guest would be protected immediately.

Initial guest support is QEMU VMs, including VMs that can later host application containers. Native LXC and application-container deployment are explicitly deferred; they need their own isolation and lifecycle decisions. Do not imply that a VM firewall separately isolates Docker containers sharing a VM.

## DNS management

Use Pi-hole v6's API for explicit A records. A name configured as `direct` resolves to its guest address; a name configured as `proxy` resolves to the selected proxy address. Multiple aliases may use different modes. Names are restricted to `{{HSP_DOMAIN}}`, are unique across the inventory, and cannot simultaneously be A and CNAME records.

Prefer explicit A records initially; CNAME support is optional, not a requirement. Proxy routing and TLS are separate from DNS. A DNS change alone does not create a proxy route or grant network access.

Read/import existing matching records before claiming them. Create, update, and delete only Terraform-owned entries. Updates must not leave stale address records; concurrent changes to the provider's shared Pi-hole configuration arrays must be serialized and tested. Preserve unrelated entries and verify a second plan has no drift.

The user clarified on 2026-10-29 that a wildcard is not required. Manage every desired name through `dns_records` and the provider's `pihole_dns_record` API resource. No Pi-hole host file, systemd service resource, or SSH configuration is part of this design.

The existing unmanaged wildcard can remain during migration. Inventory names currently relying on it, declare/import and verify their explicit records, then remove the old directive at its current source after backing up the configuration. Terraform does not change that existing directive. Inspect whether Pi-hole configuration is read-only before using API resources and verify real DNS behavior on the installed version.

Restrict the Pi-hole API to the Terraform runner. Verify the privileges needed for config writes: Pi-hole application credentials are not automatically restricted to DNS-only changes. Do not silently enable broader application API privileges.

## Credentials, state, and bootstrap inputs

Use a dedicated Proxmox API identity with the permissions required for the selected resources. Separate elevated bootstrap operations where necessary; validate TLS with a trusted certificate/CA. Provider credentials and any host SSH access are supplied outside committed configuration. Guest bootstrap uses public SSH keys rather than passwords or VPN private keys embedded in cloud-init.

For the first single-operator deployment, local Terraform state on the administrator's encrypted workstation is the proposed default, with restrictive file permissions and backups outside Git. State, plan files, private variable files, and credentials are ignored. Marking a value sensitive is not state encryption. Do not introduce a remote backend dependency on the platform being created. A remote encrypted, locking backend can be selected separately later.

Before a live plan, supply and validate the node name, exact VE version/backend, host LAN address, LAN/protected CIDRs, unused platform aggregate, existing guest networks, storage/template IDs, SSH public key, API endpoints, approved DNS/NTP targets, and initial guest inventory. These are required deployment values, not architectural decisions or placeholders to apply blindly. Never request passwords or tokens in chat.

Pi-hole's API and the initial Terraform runner must be reachable independently of a new guest. Keep bootstrap access until replacement VPN access passes live tests. Preserve existing host bridges, guests, and storage; adopt existing resources only through a reviewed import/migration plan.

## Verification and rollout

Offline checks cover Terraform formatting/validation and meaningful tests for stable slot allocation, duplicate names/addresses/IDs, subnet bounds, DNS target selection, protected-range rule order, stopped defaults, and native service triggers. Do not test merely that expressions mirror themselves.

Then use disposable guests and a disposable DNS name to verify:

1. Guest A cannot reach guest B, host management, or a home-LAN service by IPv4 or IPv6.
2. Spoofed source IP/MAC traffic is rejected, while approved DNS, time, and update traffic works.
3. An explicit proxy-to-backend rule permits only the required backend port.
4. LAN-originated access remains blocked even when public service ports are allowed.
5. An actual external connection through EdgeRouter DNAT reaches the guest and receives replies; record the source seen by the guest.
6. Unallocated aggregate destinations terminate locally rather than loop through the router.
7. Both direct/proxy names resolve as declared; updates/deletion preserve unrelated DNS entries, including during migration from the existing wildcard.
8. Removing a disposable guest cleans up its DNS, firewall, VNet, and subnet without affecting other guests; a second plan is empty.
9. Host reboot restores routing, SNAT, and filtering before managed workloads autostart.
10. Once VPN/proxy software is configured, an admin client reaches the intended management services, while a family client reaches only approved private applications and cannot reach public-only/admin applications through the private proxy.

Roll out additively. Back up current Proxmox networking/firewall and Pi-hole configuration, prepare console recovery, create a test guest, install the one router route, validate negative and positive access, and only then publish/migrate real services. No production apply is part of this design-writing step.

## Implementation discretion

The builder may choose exact supported provider versions, Terraform resource names, validation mechanisms, file layout, compatible cloud-init image/template details, and the narrow host-bootstrap implementation. These choices must preserve the boundaries and acceptance criteria above. Actual CIDRs, existing service addresses, and credentials come from deployment inventory; do not invent them.

The independent builder check asked only how Pi-hole is deployed and where the existing wildcard is owned. The installation mode is now confirmed; locating the wildcard's source is included in read-only deployment inventory. No additional architectural answer was requested by the check.

The user should specifically review these assistant proposals: per-VM `/30` networks, separate admin/service VPN gateway VMs, separate public/private proxy endpoints when needed, IPv4-only initial service addressing, VM-first container hosting, and local state for the first deployment.

## Sources checked on 2026-10-28

- [Proxmox SDN documentation](https://github.com/proxmox/pve-docs/blob/master/pvesdn.adoc): Simple zones, gateway placement, SNAT, and local port isolation.
- [Proxmox firewall documentation](https://github.com/proxmox/pve-docs/blob/master/pve-firewall.adoc): guest enforcement, interface flags, anti-spoofing, management defaults, and backend differences.
- [BPG provider requirements](https://bpg.sh/docs/): VE 9.x support and API/SSH authentication boundaries.
- [BPG SDN subnet resource](https://bpg.sh/docs/resources/sdn_subnet/): subnet/gateway/SNAT lifecycle.
- [BPG firewall IP sets](https://bpg.sh/docs/resources/virtual_environment_firewall_ipset/): managed interface address filters.
- [Pi-hole v6 provider](https://github.com/lukaspustina/terraform-provider-pihole): explicit DNS resources and config-write authentication requirements. Compatibility with the installed instance still needs a real test.
- [Pi-hole configuration reference](https://docs.pi-hole.net/ftldns/configfile/): wildcard configuration restrictions, deployment configuration, and application API privileges. Current documentation can differ from the installed component versions.
- [System provider](https://github.com/neuspaces/terraform-provider-system): candidate for tracking the small remote-file boundary over SSH, rather than using one-shot file provisioners with no drift detection.
- [Netplan gateway configuration](https://github.com/canonical/netplan/blob/main/doc/examples.md#how-to-use-a-directly-connected-gateway): explicit on-link gateway configuration when the gateway lies outside the configured interface subnet.
- [RFC 3021](https://datatracker.ietf.org/doc/html/rfc3021): two-address `/31` point-to-point links.

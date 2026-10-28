# Implementation verification

The approved infrastructure has been implemented on the local `feat/self-hosting-infrastructure` branch. No Proxmox, Pi-hole, or EdgeRouter deployment has been performed.

## Verified locally

- Terraform 1.14.8: all 10 module/environment configurations validate against the pinned provider schemas, and recursive formatting passes.
- 30 Terraform test cases pass using mock external providers and real Terraform dependency/lifecycle evaluation. These include forced zone/VNet/subnet repairs without inventory changes, file-only reload generations, converged no-op generations, address boundaries, overlap rejection, firewall order, DNS targets, and role restrictions.
- Python 3.12.14: all 19 tests pass. Coverage includes guarded CLI execution with a fake Terraform executable, API-state mismatches, stopped provisioning, private temporary plans, real TOML parsing, unrelated DNS preservation, rollback, and discovery of both deployment environments.
- CLI help commands and Git whitespace checks pass. No state, private variables, saved plans, or credentials are tracked.

Run `make init` and `make check` with Python 3.11+, or select it with `make PYTHON=python3.12 init check`.

## Independent review and fixes

A fresh reviewer inspected the complete implementation and identified four important defects. All four have been corrected in one fix pass, with each regression observed failing before its fix:

| Finding | Correction and regression |
| --- | --- |
| FTL CLI arrays were incorrectly treated as JSON | Read Pi-hole's host-local TOML with Python's standard parser; fixtures exercise real quoted TOML, embedded commas, removal, and recovery without an API read. |
| Wildcard-file-only drift did not reload the service | Change tokens now replace the service generation; a lifecycle test proves repair changes the generation exactly once. |
| Host-config was omitted from initialization and CI discovery | Discover configuration directories from any direct `.tf` file; regressions require both deployment environments and nonstandard Terraform filenames. |
| SDN object repair could remain staged | Zone/VNet/subnet resource revisions now trigger the centralized apply; forced-replacement tests prove all three repairs cause a new apply and convergence does not. |

The reviewer reported no critical findings or deferred minors. The fixes were verified by regression tests and the full suite; no second independent review was performed.

## Implementation decisions and practical costs

- Implement inline after the explicit approval/build request; no second plan-approval gate. This uses one implementation context plus an independent final reviewer.
- Initialize the new repository and keep a local feature branch in the supplied checkout. No separate worktree, remote repository, push, or merge is introduced.
- Centralize SDN creation/apply and pass prepared networks to `service_vm`. This avoids concurrent applies/dependency cycles and changes the lower-level module composition from the original sketch.
- Use bounded systemd host services and SSH/file lifecycle for routing and wildcard configuration. Deployment needs verified SSH and elevated file/service access as well as API credentials.
- Activate in a separate apply that changes only start/autostart state, after SSH host preflight and live API policy checks. Activation therefore requires a separate step and working operator SSH.
- Default host-firewall ownership off until the existing full ruleset is reviewed/imported. Activation still requires the generated protected policy to match the live host exactly, so deployment needs an explicit firewall ownership/adoption decision.
- Require Python 3.11+ for structured TOML reading without API/DNS boot dependencies or a new parser package. The default `/usr/bin/python3` on the Pi-hole host must meet that requirement before applying host configuration.

## Deployment boundaries

Live packet filtering, anti-spoofing, SDN SNAT/EdgeRouter DNAT, reboot ordering, provider behavior on the installed Pi-hole components, and real DNS updates/deletion have not been exercised. The [deployment guide](deployment.md) retains these as required disposable-resource acceptance checks before migration.

VPN/proxy/application installation, authentication, and service configuration are the explicitly deferred next phase. Their VMs and network policies can be provisioned, but this repository alone does not provide a working VPN or application endpoint.

Real addresses/template/storage inventory, the EdgeRouter static route/forwards, and inspection of existing custom DNS ownership remain deployment work. Wildcard adoption must preserve its actual current target and cannot replace a different configuration owner without an explicit migration decision.

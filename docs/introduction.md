---
slug: /
title: Introduction
description: A reading guide to the home self-hosting platform, from initial setup to deployment and verification.
---

# Home self-hosting platform

This documentation explains how to provision and operate a home self-hosting platform with Terraform, Proxmox VE 9.x, and Pi-hole v6. The platform gives each VM or LXC its own network, address, DNS records, and explicit firewall policy. An EdgeRouter provides the aggregate route and selected public port forwards.

Start with the platform overview, follow the deployment guide in order, and use the firewall reference when declaring services and access. The verification chapter explains what the repository's tests cover and what still needs checking on live infrastructure.

## Chapter index

| Chapter | What you will find |
| --- | --- |
| [1. Platform overview](chapters/platform.md) | Architecture, repository layout, inventory, DNS, and the basic Terraform workflow. |
| [2. Deployment](chapters/deployment.md) | Prerequisites, VM and LXC setup, host routing, DNS, guest activation, and acceptance checks. |
| [3. Firewall & access](chapters/firewall.md) | Guest roles, shared rules, service permissions, LAN access, proxies, and policy inspection. |
| [4. Verification](chapters/verification.md) | Local checks, recorded results, test coverage, and live verification limits. |
| [5. Engineering records](chapters/engineering.md) | The original architecture designs and implementation plans for infrastructure, LXC support, and nesting. |

Each chapter opens with an index. Individual guides also have a section index, and the sidebar follows the same reading order.

## First deployment

1. Read the [platform guide](../README.md) to understand what Terraform manages.
2. Complete the [deployment prerequisites](deployment.md#prerequisites) and [configure the environments](deployment.md#configure-and-initialize).
3. Review [roles and shared firewall rules](firewall-roles.md) before exposing services.
4. Follow the deployment guide through provisioning, inspection, first start, and [live acceptance](deployment.md#live-acceptance-and-removal).

New guests default to stopped. VPN services, reverse proxies, application software, backup schedules, and existing workload migration need their own configuration, as described in the guides.

## Reading the engineering records

The deployment and firewall guides describe the current configuration. The engineering records preserve the earlier designs and implementation plans, including decisions that evolved during implementation. Read them for context alongside the current guides and verification history.

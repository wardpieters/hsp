#!/usr/bin/env python3
"""Plan, provision stopped guests, and activate only after checking live enforcement."""
import argparse
from contextlib import contextmanager
import ipaddress
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request


VM = "proxmox_virtual_environment_vm"
OPTIONS = "proxmox_virtual_environment_firewall_options"
RULES = "proxmox_virtual_environment_firewall_rules"
IPSET = "proxmox_virtual_environment_firewall_ipset"


def changes(plan, kind):
    return [r for r in plan.get("resource_changes", []) if r.get("type") == kind and r["change"].get("after") is not None]


def owned(plan, kind, vm):
    entries = [r["change"]["after"] for r in changes(plan, kind)
               if r["change"]["after"].get("node_name") == vm.get("node_name")
               and r["change"]["after"].get("vm_id") == vm.get("vm_id")]
    if len(entries) != 1:
        raise ValueError("Exactly one owned " + kind + " is required for VM " + str(vm.get("vm_id")))
    return entries[0]


def guest_ip(vm):
    address = vm["initialization"][0]["ip_config"][0]["ipv4"][0]["address"]
    return str(ipaddress.IPv4Interface(address).ip) + "/32"


def validate_plan(plan, activating=False):
    errors = []
    for resource in changes(plan, VM):
        change = resource["change"]
        vm, before = change["after"], change.get("before") or {}
        label = resource["address"]
        try:
            if change.get("after_unknown", {}).get("started") or change.get("after_unknown", {}).get("on_boot"):
                raise ValueError("Unknown activation state is not allowed")
            if "create" in change["actions"] and (vm.get("started") is not False or vm.get("on_boot") is not False):
                raise ValueError("Create/replacement must provision stopped with autostart disabled")
            starting = vm.get("started") is True and before.get("started") is not True
            autostart = vm.get("on_boot") is True and before.get("on_boot") is not True
            if (starting or autostart) and not activating:
                raise ValueError("Use activate after a separate stopped-provision apply")
            interfaces = vm.get("network_device") or []
            if len(interfaces) != 1 or interfaces[0].get("firewall") is not True:
                raise ValueError("Exactly one firewall-enabled NIC is required")
            options = owned(plan, OPTIONS, vm)
            required = {"enabled": True, "macfilter": True, "ipfilter": True, "dhcp": False, "ndp": False, "radv": False,
                        "input_policy": "DROP", "output_policy": "DROP"}
            if any(options.get(k) != v for k, v in required.items()):
                raise ValueError("Guest firewall options are not fail-closed")
            ipset = owned(plan, IPSET, vm)
            if ipset.get("name") != "ipfilter-net0" or [(r.get("name"), bool(r.get("nomatch"))) for r in ipset.get("cidr", [])] != [(guest_ip(vm), False)]:
                raise ValueError("The source filter must contain only the assigned guest /32")
            rules = owned(plan, RULES, vm).get("rule") or []
            if len(rules) < 2 or rules[0].get("source") != "::/0" or rules[1].get("dest") != "::/0" or any(rules[i].get("action") != "DROP" or rules[i].get("enabled") is not True for i in (0, 1)):
                raise ValueError("Explicit enabled IPv6 drops must lead the policy")
        except (ValueError, KeyError, IndexError, TypeError) as error:
            errors.append(label + ": " + str(error))
    if activating:
        computed = {"ipv4_addresses", "ipv6_addresses", "mac_addresses", "network_interface_names"}
        for resource in plan.get("resource_changes", []):
            change = resource["change"]
            if change["actions"] == ["no-op"]:
                continue
            if resource.get("type") != VM or change["actions"] != ["update"]:
                errors.append("Activation must contain only existing VM start/autostart updates: " + resource["address"])
                continue
            before, after = change.get("before") or {}, change.get("after") or {}
            altered = {k for k in before.keys() | after.keys() if before.get(k) != after.get(k)} - computed
            if altered - {"started", "on_boot"}:
                errors.append("Provision policy/network changes separately before activation: " + resource["address"])
    return errors


def normalize_rules(rows, api=False):
    keys = ["type", "action", "source", "dest", "proto", "dport", "iface", "comment"]
    result = []
    for row in sorted(rows, key=lambda r: r.get("pos", 0)) if api else rows:
        data = {k: str(row[k]) for k in keys if row.get(k) is not None and row[k] != ""}
        data["enabled"] = row.get("enable" if api else "enabled") in (True, 1, "1")
        result.append(data)
    return result


def verify_activation(plan, api_client):
    context = plan.get("planned_values", {}).get("outputs", {}).get("activation_context", {}).get("value")
    if not context:
        raise ValueError("The home environment's activation_context output is required")
    if not str(api_client("/version").get("version", "")).startswith("9."):
        raise ValueError("Expected Proxmox VE 9.x")
    global_options = api_client("/cluster/firewall/options")
    if global_options.get("enable") not in (1, True) or global_options.get("ebtables") not in (1, True):
        raise ValueError("Datacenter firewall/MAC filtering are not enabled")
    checked_nodes = set()
    for resource in changes(plan, VM):
        vm, before = resource["change"]["after"], resource["change"].get("before") or {}
        if not ((vm.get("started") and not before.get("started")) or (vm.get("on_boot") and not before.get("on_boot"))):
            continue
        node = vm["node_name"]
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", node):
            raise ValueError("Invalid node identity")
        if node not in checked_nodes:
            opts = api_client("/nodes/" + node + "/firewall/options")
            if opts.get("enable") not in (1, True) or opts.get("nftables", 0) not in (0, False):
                raise ValueError("Expected the enabled established node firewall backend")
            expected = context.get("host_rules") or []
            if not any(r.get("comment") == "hsp:host:deny-platform" for r in expected):
                raise ValueError("An explicit host policy protecting the aggregate is required")
            actual = api_client("/nodes/" + node + "/firewall/rules")
            if normalize_rules(actual, api=True) != normalize_rules(expected):
                raise ValueError("Live host firewall differs from the reviewed policy")
            checked_nodes.add(node)
        prefix = "/nodes/" + node + "/qemu/" + str(int(vm["vm_id"]))
        config = api_client(prefix + "/config")
        if [k for k in config if re.fullmatch(r"net\d+", k)] != ["net0"]:
            raise ValueError("Unexpected live NICs, including inherited template interfaces")
        net = dict(part.split("=", 1) for part in config["net0"].split(",") if "=" in part)
        if net.get("firewall") != "1" or net.get("bridge") != vm["network_device"][0]["bridge"]:
            raise ValueError("Live NIC enforcement/bridge does not match")
        ipconfig = dict(part.split("=", 1) for part in config.get("ipconfig0", "").split(",") if "=" in part)
        expected_ip = vm["initialization"][0]["ip_config"][0]["ipv4"][0]["address"]
        if ipconfig.get("ip") != expected_ip:
            raise ValueError("Live cloud-init address does not match the assigned guest address")
        if any(re.fullmatch(r"(hostpci|usb|virtiofs)\d+", k) for k in config):
            raise ValueError("Unexpected host device passthrough inherited from the template")
        opts = api_client(prefix + "/firewall/options")
        expected = {"enable": 1, "policy_in": "DROP", "policy_out": "DROP", "macfilter": 1, "ipfilter": 1, "dhcp": 0, "ndp": 0, "radv": 0}
        if any(opts.get(k) != value for k, value in expected.items()):
            raise ValueError("Live VM firewall options do not match the fail-closed policy")
        rows = api_client(prefix + "/firewall/ipset/ipfilter-net0")
        if [(r.get("cidr"), bool(r.get("nomatch"))) for r in rows] != [(guest_ip(vm), False)]:
            raise ValueError("Live anti-spoofing filter differs from the assigned /32")
        actual = api_client(prefix + "/firewall/rules")
        if normalize_rules(actual, api=True) != normalize_rules(owned(plan, RULES, vm)["rule"]):
            raise ValueError("Live VM policy differs from the reviewed policy")


class ProxmoxAPI:
    def __init__(self, endpoint, token):
        parsed = urllib.parse.urlsplit(endpoint)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError("Proxmox requires an HTTPS endpoint without embedded credentials")
        if not token or "=" not in token or "\n" in token:
            raise ValueError("Set PROXMOX_VE_API_TOKEN outside the configuration")
        self.endpoint = endpoint.rstrip("/") + "/api2/json"
        self.token = token
        self.context = ssl.create_default_context()

    def __call__(self, path):
        request = urllib.request.Request(self.endpoint + path, headers={"Authorization": "PVEAPIToken=" + self.token})
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=20) as response:
                data = json.load(response)
            return data["data"]
        except (urllib.error.URLError, KeyError, json.JSONDecodeError) as error:
            raise ValueError("Proxmox verification failed for " + path + " (" + type(error).__name__ + ")") from None


@contextmanager
def private_plan_directory():
    with tempfile.TemporaryDirectory(prefix="hsp-plan-") as directory:
        os.chmod(directory, 0o700)
        yield Path(directory)


def host_preflight(context):
    target = os.environ.get("HSP_PROXMOX_SSH", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+", target):
        raise ValueError("Set HSP_PROXMOX_SSH=user@host for the verified host routing preflight")
    cidr = str(ipaddress.IPv4Network(context["platform_cidr"], strict=True))
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", target,
                    "sudo", "-n", "/usr/bin/python3", "/usr/local/sbin/hsp-host-config-proxmox", "check", "proxmox", "/etc/hsp-proxmox.json", "--expected-cidr", cidr], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply", "activate"])
    parser.add_argument("--directory", type=Path, default=Path("environments/home"))
    parser.add_argument("--var-file", type=Path, required=True)
    parser.add_argument("--yes", action="store_true", help="Explicitly approve applying the inspected plan without a prompt")
    args = parser.parse_args()
    directory, varfile = args.directory.resolve(), args.var_file.resolve()
    if not varfile.is_file():
        parser.error("The private variable file must exist")
    os.umask(0o077)
    try:
        with private_plan_directory() as folder:
            planfile = folder / "reviewed.tfplan"
            command = ["terraform", "-chdir=" + str(directory)]
            subprocess.run(command + ["plan", "-input=false", "-parallelism=1", "-var-file=" + str(varfile), "-out=" + str(planfile)], check=True)
            result = subprocess.run(command + ["show", "-json", str(planfile)], check=True, capture_output=True, text=True)
            plan = json.loads(result.stdout)
            errors = validate_plan(plan, activating=args.action == "activate")
            if errors:
                raise ValueError("Plan rejected:\n" + "\n".join(errors))
            if args.action == "plan":
                print("Plan checked; no changes applied. Re-run apply to generate and review a fresh saved plan.")
                return
            if not args.yes and input("Apply the inspected plan? Type apply: ") != "apply":
                raise ValueError("Apply cancelled")
            if args.action == "activate":
                context = plan["planned_values"]["outputs"]["activation_context"]["value"]
                host_preflight(context)
                verify_activation(plan, ProxmoxAPI(context["endpoint"], os.environ.get("PROXMOX_VE_API_TOKEN")))
            subprocess.run(command + ["apply", "-input=false", "-parallelism=1", str(planfile)], check=True)
    except (ValueError, subprocess.CalledProcessError, EOFError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()

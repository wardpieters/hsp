#!/usr/bin/env python3
"""Bounded host configuration for hsp. Run on the intended Linux host as root.

Only the dedicated hsp files and the one Pi-hole include are owned here.
No credentials or complete Pi-hole configuration are returned to Terraform.
"""
import argparse
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import tempfile


INCLUDE = "conf-file=/etc/pihole/hsp-dns.conf"
DOMAIN = "home.ward.nl"


def private_network(value):
    network = ipaddress.IPv4Network(value, strict=True)
    ranges = [ipaddress.IPv4Network(c) for c in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    if network.prefixlen > 30 or not any(network.subnet_of(r) for r in ranges):
        raise ValueError("Expected a canonical RFC1918 aggregate with prefix <= 30")
    return str(network)


def run(args):
    result = subprocess.run(args, check=True, capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def atomic_write(path, content, mode=0o600):
    path = Path(path)
    previous = path.stat() if path.exists() else None
    fd, temporary = tempfile.mkstemp(prefix=".hsp-", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        if previous is not None:
            os.fchown(fd, previous.st_uid, previous.st_gid)
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def wildcard_target(line):
    if not line.startswith("address=/"):
        return None
    fields = line.split("/")
    domains = [d.lstrip(".") for d in fields[1:-1]]
    if DOMAIN not in domains:
        return None
    if len(domains) != 1:
        raise ValueError("The existing wildcard shares a directive with other domains; split it before adoption")
    return fields[-1]


def reconcile_lines(lines, target, remove=False):
    if not isinstance(lines, list) or not all(isinstance(line, str) for line in lines):
        raise ValueError("Pi-hole did not return a string-array configuration")
    result = []
    owners = 0
    for line in lines:
        if line == INCLUDE:
            owners += 1
            continue
        existing = wildcard_target(line)
        if existing is not None and not remove:
            if existing != target:
                raise ValueError("The existing wildcard points elsewhere; preserve its target during adoption")
            owners += 1
            continue
        result.append(line)
    if owners > 1:
        raise ValueError("Multiple wildcard owners found; resolve the conflict before adoption")
    if not remove:
        result.append(INCLUDE)
    return result


def configure_pihole(config, root=Path("/"), runner=run, remove=False):
    root = Path(root)
    folder = root / "etc/pihole"
    toml = folder / "pihole.toml"
    managed = folder / "hsp-dns.conf"
    good = folder / "hsp-dns.conf.last-good"
    target = str(ipaddress.IPv4Address(config["proxy_address"])) if not remove else ""
    if not remove:
        # Tests/legacy files may omit the generated comment; validate effective directives.
        directives = [line for line in managed.read_text().splitlines() if line and not line.startswith("#")]
        if directives != ["address=/" + DOMAIN + "/" + target]:
            raise ValueError("Managed wildcard file does not match its declared target")
    original = toml.read_bytes()
    lines = json.loads(runner(["pihole-FTL", "--config", "misc.dnsmasq_lines"]))
    desired = reconcile_lines(lines, target, remove)
    legacy = None
    original_legacy = None
    if config.get("legacy_file"):
        path = Path(config["legacy_file"])
        if not path.is_absolute() or path.parent != Path("/etc/dnsmasq.d") or path.suffix != ".conf":
            raise ValueError("legacy_file must identify one .conf file directly inside /etc/dnsmasq.d")
        legacy = root / str(path).lstrip("/")
        original_legacy = legacy.read_bytes()
        old_lines = original_legacy.decode().splitlines(keepends=True)
        selected = [line for line in old_lines if wildcard_target(line.strip()) is not None]
        if len(selected) > 1 or any(wildcard_target(line.strip()) != target for line in selected):
            raise ValueError("Legacy wildcard ownership/target is ambiguous")
    # Refuse unadopted legacy directives rather than silently introduce duplicate ownership.
    if not remove:
        for path in (root / "etc/dnsmasq.d").glob("*.conf"):
            if path != legacy and any(wildcard_target(line.strip()) is not None for line in path.read_text().splitlines()):
                raise ValueError("A legacy wildcard file needs explicit legacy_file adoption")
    atomic_write(folder / "pihole.toml.hsp-backup", original)
    try:
        if legacy is not None and not remove:
            kept = "".join(line for line in original_legacy.decode().splitlines(keepends=True) if wildcard_target(line.strip()) is None)
            atomic_write(legacy, kept.encode(), 0o644)
        runner(["pihole-FTL", "--config", "misc.dnsmasq_lines", json.dumps(desired)])
        runner(["pihole-FTL", "dnsmasq-test"])
        runner(["systemctl", "restart", "pihole-FTL.service"])
        if not remove:
            atomic_write(good, managed.read_bytes(), 0o644)
    except Exception:
        atomic_write(toml, original, toml.stat().st_mode & 0o777)
        if legacy is not None and original_legacy is not None:
            atomic_write(legacy, original_legacy, 0o644)
        if good.exists():
            atomic_write(managed, good.read_bytes(), 0o644)
        # Best-effort recovery never hides the original failure.
        try:
            runner(["systemctl", "restart", "pihole-FTL.service"])
        except Exception:
            pass
        raise


def configure_proxmox(config, runner=run, remove=False):
    cidr = private_network(config["platform_cidr"])
    if remove:
        routes = json.loads(runner(["ip", "-j", "-4", "route", "show", "exact", cidr]))
        if any(r.get("type") == "blackhole" and r.get("metric") == 42760 for r in routes):
            runner(["ip", "-4", "route", "del", "blackhole", cidr, "metric", "42760"])
        return
    runner(["systemctl", "is-active", "--quiet", "pve-firewall.service"])
    runner(["sysctl", "-w", "net.ipv4.ip_forward=1"])
    runner(["ip", "-4", "route", "replace", "blackhole", cidr, "metric", "42760"])


def check(config, kind, root=Path("/"), runner=run):
    if kind == "proxmox":
        cidr = private_network(config["platform_cidr"])
        routes = json.loads(runner(["ip", "-j", "-4", "route", "show", "exact", cidr]))
        if runner(["sysctl", "-n", "net.ipv4.ip_forward"]) != "1" or not any(r.get("type") == "blackhole" and r.get("metric") == 42760 for r in routes):
            raise ValueError("Persistent forwarding/aggregate blackhole is not active")
    else:
        target = str(ipaddress.IPv4Address(config["proxy_address"]))
        lines = json.loads(runner(["pihole-FTL", "--config", "misc.dnsmasq_lines"]))
        if lines.count(INCLUDE) != 1 or any(wildcard_target(line) is not None for line in lines):
            raise ValueError("The managed include is not the sole wildcard owner")
        path = Path(root) / "etc/pihole/hsp-dns.conf"
        directives = [s for s in path.read_text().splitlines() if s and not s.startswith("#")]
        if directives != ["address=/" + DOMAIN + "/" + target]:
            raise ValueError("The managed wildcard has drifted")
        runner(["pihole-FTL", "dnsmasq-test"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "remove", "check"])
    parser.add_argument("kind", choices=["proxmox", "pihole"])
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run this bounded host helper as root")
    config = json.loads(args.config.read_text())
    with open("/run/lock/hsp-" + args.kind + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "check":
            check(config, args.kind)
        elif args.kind == "proxmox":
            configure_proxmox(config, remove=args.action == "remove")
        else:
            configure_pihole(config, remove=args.action == "remove")
    print("hsp " + args.kind + " " + args.action + ": verified")


if __name__ == "__main__":
    main()

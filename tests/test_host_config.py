import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/host_config.py"


class HostConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SCRIPT.exists():
            raise AssertionError("The host configuration helper must exist")
        spec = importlib.util.spec_from_file_location("host_config", SCRIPT)
        cls.host = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.host)

    def test_preserves_unrelated_dns_directives(self):
        result = self.host.reconcile_lines(
            ["server=/other.test/192.168.1.2", "address=/home.ward.nl/10.77.0.2"],
            "10.77.0.2", False,
        )
        self.assertEqual(result, ["server=/other.test/192.168.1.2", "conf-file=/etc/pihole/hsp-dns.conf"])

    def test_refuses_different_existing_wildcard_target(self):
        with self.assertRaises(ValueError):
            self.host.reconcile_lines(["address=/home.ward.nl/192.168.1.2"], "10.77.0.2", False)

    def test_rejects_nonprivate_or_injectable_route(self):
        for cidr in ["0.0.0.0/0", "203.0.113.0/24", "10.0.0.1/24", "10.0.0.0/24;reboot"]:
            with self.subTest(cidr=cidr), self.assertRaises(ValueError):
                self.host.private_network(cidr)

    def test_failed_reload_restores_previous_dns_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            p = root / "etc/pihole"
            p.mkdir(parents=True)
            original = b'# keep passwords and comments private\n[misc]\ndnsmasq_lines = []\n'
            (p / "pihole.toml").write_bytes(original)
            (p / "hsp-dns.conf").write_text("address=/home.ward.nl/10.77.0.6\n")
            (p / "hsp-dns.conf.last-good").write_text("address=/home.ward.nl/10.77.0.2\n")

            def runner(args):
                if args == ["pihole-FTL", "--config", "misc.dnsmasq_lines"]:
                    return "[]"
                if len(args) == 4 and args[:3] == ["pihole-FTL", "--config", "misc.dnsmasq_lines"]:
                    (p / "pihole.toml").write_text("changed\n")
                if args == ["systemctl", "restart", "pihole-FTL.service"]:
                    raise RuntimeError("reload failed")
                return ""

            with self.assertRaises(RuntimeError):
                self.host.configure_pihole({"proxy_address": "10.77.0.6"}, root, runner)
            self.assertEqual((p / "pihole.toml").read_bytes(), original)
            self.assertEqual((p / "hsp-dns.conf").read_text(), "address=/home.ward.nl/10.77.0.2\n")

    def test_remove_unregisters_include_before_managed_file_disappears(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "etc/pihole").mkdir(parents=True)
            (root / "etc/pihole/pihole.toml").write_text("existing\n")
            changed = []

            def runner(args):
                if len(args) == 3:
                    return json.dumps(["server=192.168.1.2", "conf-file=/etc/pihole/hsp-dns.conf"])
                if args[:3] == ["pihole-FTL", "--config", "misc.dnsmasq_lines"]:
                    changed.extend(json.loads(args[3]))
                return ""

            self.host.configure_pihole({}, root, runner, remove=True)
            self.assertEqual(changed, ["server=192.168.1.2"])


if __name__ == "__main__":
    unittest.main()

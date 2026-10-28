import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/hsp.py"


def fixture():
    vm = {"node_name": "pve", "vm_id": 100, "started": False, "on_boot": False,
          "network_device": [{"firewall": True, "bridge": "hsp100"}],
          "initialization": [{"ip_config": [{"ipv4": [{"address": "10.77.0.2/30"}]}]}]}
    options = {"node_name": "pve", "vm_id": 100, "enabled": True, "input_policy": "DROP",
               "output_policy": "DROP", "macfilter": True, "ipfilter": True, "dhcp": False, "ndp": False, "radv": False}
    rules = [{"type": "in", "action": "DROP", "source": "::/0", "enabled": True, "iface": "net0", "comment": "hsp:ipv6-in"},
             {"type": "out", "action": "DROP", "dest": "::/0", "enabled": True, "iface": "net0", "comment": "hsp:ipv6-out"}]
    resources = [
        ("proxmox_virtual_environment_vm", vm),
        ("proxmox_virtual_environment_firewall_options", options),
        ("proxmox_virtual_environment_firewall_ipset", {"node_name": "pve", "vm_id": 100, "name": "ipfilter-net0", "cidr": [{"name": "10.77.0.2/32", "nomatch": False}]}),
        ("proxmox_virtual_environment_firewall_rules", {"node_name": "pve", "vm_id": 100, "rule": rules}),
    ]
    return {"resource_changes": [{"type": kind, "address": kind + ".this", "change": {"actions": ["create"], "before": None, "after": data, "after_unknown": {}}} for kind, data in resources]}


class GuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SCRIPT.exists():
            raise AssertionError("The guarded operator workflow must exist")
        spec = importlib.util.spec_from_file_location("hsp", SCRIPT)
        cls.hsp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.hsp)

    def test_stopped_provision_is_allowed(self):
        self.assertEqual(self.hsp.validate_plan(fixture()), [])

    def test_refuses_initial_running_and_replacement(self):
        for actions in (["create"], ["delete", "create"]):
            p = fixture()
            p["resource_changes"][0]["change"]["actions"] = actions
            p["resource_changes"][0]["change"]["after"]["started"] = True
            self.assertTrue(self.hsp.validate_plan(p))

    def test_refuses_autostart_on_new_guest(self):
        p = fixture()
        p["resource_changes"][0]["change"]["after"]["on_boot"] = True
        self.assertTrue(self.hsp.validate_plan(p))

    def test_refuses_missing_or_disabled_firewall(self):
        for field in ["missing", "enabled", "macfilter", "ipfilter"]:
            p = fixture()
            if field == "missing":
                p["resource_changes"].pop(1)
            else:
                p["resource_changes"][1]["change"]["after"][field] = False
            self.assertTrue(self.hsp.validate_plan(p), field)

    def test_refuses_extra_interface_and_spoofable_ipset(self):
        p = fixture()
        p["resource_changes"][0]["change"]["after"]["network_device"].append({"firewall": False})
        self.assertTrue(self.hsp.validate_plan(p))
        p = fixture()
        p["resource_changes"][2]["change"]["after"]["cidr"][0]["name"] = "10.77.0.0/24"
        self.assertTrue(self.hsp.validate_plan(p))

    def test_existing_running_guest_does_not_block_provision(self):
        p = fixture()
        change = p["resource_changes"][0]["change"]
        change["after"]["started"] = True
        change["before"] = copy.deepcopy(change["after"])
        change["actions"] = ["no-op"]
        self.assertEqual(self.hsp.validate_plan(p), [])

    def test_activation_cannot_change_firewall_in_same_apply(self):
        p = fixture()
        change = p["resource_changes"][0]["change"]
        change["before"] = copy.deepcopy(change["after"])
        change["after"]["started"] = True
        change["actions"] = ["update"]
        self.assertTrue(self.hsp.validate_plan(p, activating=True))

    def test_activation_requires_live_matching_policy(self):
        p = fixture()
        change = p["resource_changes"][0]["change"]
        change["before"] = copy.deepcopy(change["after"])
        change["after"]["started"] = True
        change["actions"] = ["update"]
        for entry in p["resource_changes"][1:]:
            entry["change"]["actions"] = ["no-op"]
        p["planned_values"] = {"outputs": {"activation_context": {"value": {"platform_cidr": "10.77.0.0/24", "host_rules": []}}}}
        # API errors/missing enforcement must fail closed, never turn into an approval.
        with self.assertRaises(ValueError):
            self.hsp.verify_activation(p, lambda path: {})

    def test_private_plan_directory(self):
        with self.hsp.private_plan_directory() as path:
            self.assertEqual(Path(path).stat().st_mode & 0o777, 0o700)
        self.assertFalse(Path(path).exists())

    def test_activation_accepts_verified_existing_enforcement(self):
        p = fixture()
        vm = p["resource_changes"][0]["change"]
        vm["before"] = copy.deepcopy(vm["after"])
        vm["after"]["started"] = True
        vm["actions"] = ["update"]
        for entry in p["resource_changes"][1:]:
            entry["change"]["actions"] = ["no-op"]
        host_rules = [{"type": "in", "action": "DROP", "source": "10.77.0.0/24", "enabled": True, "comment": "hsp:host:deny-platform"}]
        p["planned_values"] = {"outputs": {"activation_context": {"value": {"platform_cidr": "10.77.0.0/24", "host_rules": host_rules}}}}
        rules = [{("enable" if k == "enabled" else k): v for k, v in row.items()} for row in p["resource_changes"][3]["change"]["after"]["rule"]]
        replies = {
            "/version": {"version": "9.1.0"},
            "/cluster/firewall/options": {"enable": 1, "ebtables": 1},
            "/nodes/pve/firewall/options": {"enable": 1, "nftables": 0},
            "/nodes/pve/firewall/rules": [{"type": "in", "action": "DROP", "source": "10.77.0.0/24", "enable": 1, "comment": "hsp:host:deny-platform"}],
            "/nodes/pve/qemu/100/config": {"net0": "virtio=02:00:00:00:00:01,bridge=hsp100,firewall=1", "ipconfig0": "ip=10.77.0.2/30,gw=10.77.0.1"},
            "/nodes/pve/qemu/100/firewall/options": {"enable": 1, "policy_in": "DROP", "policy_out": "DROP", "macfilter": 1, "ipfilter": 1, "ndp": 0, "dhcp": 0, "radv": 0},
            "/nodes/pve/qemu/100/firewall/ipset/ipfilter-net0": [{"cidr": "10.77.0.2/32", "nomatch": 0}],
            "/nodes/pve/qemu/100/firewall/rules": rules,
        }
        self.assertEqual(self.hsp.validate_plan(p, activating=True), [])
        self.hsp.verify_activation(p, lambda path: copy.deepcopy(replies[path]))
        replies["/nodes/pve/qemu/100/config"]["ipconfig0"] = "ip=10.77.0.99/30,gw=10.77.0.1"
        with self.assertRaises(ValueError):
            self.hsp.verify_activation(p, lambda path: copy.deepcopy(replies[path]))
        replies["/nodes/pve/qemu/100/config"]["ipconfig0"] = "ip=10.77.0.2/30,gw=10.77.0.1"
        replies["/nodes/pve/qemu/100/config"]["net1"] = "virtio=02:00:00:00:00:02,bridge=vmbr0"
        with self.assertRaises(ValueError):
            self.hsp.verify_activation(p, lambda path: copy.deepcopy(replies[path]))


if __name__ == "__main__":
    unittest.main()

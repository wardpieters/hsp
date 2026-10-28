import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check", ROOT / "scripts/check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class ConfigurationDiscoveryTests(unittest.TestCase):
    def test_both_deployment_environments_are_initialized_and_checked(self):
        folders = check.configuration_directories(ROOT)
        self.assertIn(ROOT / "environments/home", folders)
        self.assertIn(ROOT / "environments/host-config", folders)

    def test_discovery_does_not_depend_on_terraform_filename(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, filename in [("environments/host", "main.tf"), ("modules/example", "resources.tf")]:
                path = root / name
                path.mkdir(parents=True)
                (path / filename).write_text("")
            self.assertEqual(check.configuration_directories(root), [root / "environments/host", root / "modules/example"])

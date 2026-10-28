#!/usr/bin/env python3
"""Initialize or validate all Terraform configurations; tests use mock providers."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def configuration_directories(root=ROOT):
    return sorted({p.parent for base in ("modules", "environments") for p in (root / base).glob("*/*.tf")})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["init", "check"])
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        parser.error("Python 3.11+ is required for the host helper's standard TOML parser; select it with make PYTHON=python3.12")
    folders = configuration_directories()
    if args.action == "check":
        subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], cwd=ROOT, check=True)
        subprocess.run(["terraform", "fmt", "-check", "-recursive"], cwd=ROOT, check=True)
    for folder in folders:
        print(str(folder.relative_to(ROOT)), flush=True)
        base = ["terraform", "-chdir=" + str(folder)]
        if args.action == "init":
            command = base + ["init", "-backend=false", "-input=false"]
            if os.environ.get("HSP_PLUGIN_DIR"):
                command.append("-plugin-dir=" + os.environ["HSP_PLUGIN_DIR"])
            subprocess.run(command, check=True)
        else:
            subprocess.run(base + ["validate", "-no-color"], check=True)
            subprocess.run(base + ["test", "-no-color"], check=True)


if __name__ == "__main__":
    main()

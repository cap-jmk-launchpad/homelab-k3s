#!/usr/bin/env python3
"""Merge DEPTRACK_* keys from a remote launchpad .env into the local launchpad .env."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

KEY_RE = re.compile(r"^DEPTRACK_[A-Z0-9_]+=(.*)$")


def set_key(lines: list[str], key: str, value: str) -> list[str]:
    prefix = f"{key}="
    out: list[str] = []
    found = False
    for line in lines:
        if line.startswith(prefix):
            out.append(f"{key}={value}\n")
            found = True
        else:
            out.append(line if line.endswith("\n") else line + "\n")
    if not found:
        if out and not out[-1].endswith("\n\n"):
            out.append("\n")
        out.append(f"{key}={value}\n")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-env", type=Path, required=True)
    parser.add_argument("--remote-env", default="~/launchpad/.env")
    parser.add_argument("--ssh-host", default="blackpearl")
    parser.add_argument("--ssh-user", default="s4il0r")
    parser.add_argument("--ssh-key", type=Path, required=True)
    args = parser.parse_args()

    cmd = [
        "ssh",
        "-i",
        str(args.ssh_key),
        "-o",
        "IdentitiesOnly=yes",
        f"{args.ssh_user}@{args.ssh_host}",
        f"grep '^DEPTRACK_' {args.remote_env}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
    remote_pairs: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        m = KEY_RE.match(line.strip())
        if m:
            key, _, val = line.strip().partition("=")
            remote_pairs[key] = val

    if not remote_pairs:
        print("No DEPTRACK_* keys found on remote", file=sys.stderr)
        return 1

    local = args.local_env
    lines = local.read_text(encoding="utf-8").splitlines(keepends=True) if local.exists() else []
    for key, val in sorted(remote_pairs.items()):
        lines = set_key(lines, key, val)
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_text("".join(lines), encoding="utf-8")
    print(f"Merged {len(remote_pairs)} DEPTRACK_* keys into {local}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

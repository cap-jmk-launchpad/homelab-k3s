#!/usr/bin/env python3
"""Run df/lsblk on all homelab nodes via SSH from blackpearl."""
import subprocess

NODES = [
    ("anch0r", 22, "192.168.10.22"),
    ("deck", 22, "192.168.10.26"),
    ("desktop", 2222, "192.168.10.31"),
    ("engine", 22, "192.168.10.32"),
    ("blackpearl", 22, "192.168.10.33"),
]
CMD = "df -hT -x tmpfs -x devtmpfs; echo; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS"

for name, port, host in NODES:
    print(f"=== {name} ({host}) ===")
    try:
        out = subprocess.check_output(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-p", str(port),
             f"s4il0r@{host}", CMD],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
        print(out[:2500])
    except Exception as e:
        print(f"(failed: {e})")
    print()

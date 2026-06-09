#!/usr/bin/env python3
"""Put gitlab upstream_peer first so li-httpd registers pool before HTTPD_MAX_UPSTREAM_PEERS edge cases."""
from __future__ import annotations

import sys
from pathlib import Path


def reorder(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    peers = [line for line in lines if line.startswith("upstream_peer=")]
    balances = [line for line in lines if line.startswith("upstream_balance=")]
    other = [line for line in lines if line not in peers and line not in balances]
    prio = [line for line in peers if line.startswith("upstream_peer=gitlab|")]
    rest = [line for line in peers if line not in prio]
    ordered = other + prio + rest + balances
    path.write_text("\n".join(ordered) + "\n", encoding="utf-8")
    gitlab_n = len(prio)
    print(
        f"reorder-upstream-peers: gitlab first ({gitlab_n}/{len(peers)} peers) -> {path}",
        file=sys.stderr,
    )


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "/run/li-httpd/homelab.runtime.conf")
    reorder(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

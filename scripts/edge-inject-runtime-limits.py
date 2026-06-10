#!/usr/bin/env python3
"""Inject [limits] stream keys from merged edge TOML into flattened runtime.conf.

li-httpd multi-site flatten emits byte caps via limits_flatten_lines but not
concurrent_streams / stream_idle / stream_max_duration. Edge homelab needs these
for g_active_proxy_streams and parallel pump bypass.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

try:
    from httpd_m15 import parse_duration
except ImportError:
    def parse_duration(raw: object, field: str) -> int:
        s = str(raw).strip().rstrip("s")
        if not s.isdigit():
            raise ValueError(f"{field}: invalid duration {raw!r}")
        return int(s)


def _existing_keys(lines: list[str]) -> set[str]:
    keys: set[str] = set()
    for line in lines:
        if "=" in line:
            keys.add(line.split("=", 1)[0])
    return keys


def _insert_after(lines: list[str], prefix: str, new_lines: list[str]) -> list[str]:
    if not new_lines:
        return lines
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return lines[: i + 1] + new_lines + lines[i + 1 :]
    return new_lines + lines


def inject_limits(toml_path: Path, conf_path: Path) -> int:
    data = tomllib.loads(toml_path.read_text(encoding="utf-8"))
    limits = data.get("limits") or {}
    if not isinstance(limits, dict):
        return 0

    lines = conf_path.read_text(encoding="utf-8").splitlines()
    existing = _existing_keys(lines)
    additions: list[str] = []

    if limits.get("concurrent_streams") is not None and "concurrent_streams" not in existing:
        additions.append(f"concurrent_streams={int(limits['concurrent_streams'])}")
    if limits.get("stream_idle_timeout") is not None and "stream_idle_timeout_sec" not in existing:
        additions.append(
            f"stream_idle_timeout_sec={parse_duration(limits['stream_idle_timeout'], 'limits.stream_idle_timeout')}"
        )
    if limits.get("stream_max_duration") is not None and "stream_max_duration_sec" not in existing:
        additions.append(
            f"stream_max_duration_sec={parse_duration(limits['stream_max_duration'], 'limits.stream_max_duration')}"
        )

    if not additions:
        return 0

    anchor = "max_proxy_response_body_bytes="
    if not any(l.startswith(anchor) for l in lines):
        anchor = "health_fail_timeout_sec="
    if not any(l.startswith(anchor) for l in lines):
        anchor = "document_root="
    lines = _insert_after(lines, anchor, additions)
    conf_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"edge-inject-runtime-limits: {conf_path.name} +{len(additions)} ({', '.join(additions)})")
    return len(additions)


def main() -> int:
    p = argparse.ArgumentParser(description="inject edge [limits] stream keys into runtime.conf")
    p.add_argument("toml", type=Path, help="merged homelab.httpd.toml")
    p.add_argument("conf", type=Path, nargs="+", help="runtime.conf file(s) to patch")
    args = p.parse_args()
    if not args.toml.is_file():
        print(f"edge-inject-runtime-limits: missing {args.toml}", file=sys.stderr)
        return 1
    total = 0
    for conf in args.conf:
        if not conf.is_file():
            print(f"edge-inject-runtime-limits: skip missing {conf}", file=sys.stderr)
            continue
        total += inject_limits(args.toml, conf)
    return 0 if total >= 0 else 1


if __name__ == "__main__":
    sys.exit(main())

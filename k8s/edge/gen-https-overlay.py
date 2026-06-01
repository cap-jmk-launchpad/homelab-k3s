#!/usr/bin/env python3
"""Build a :443 + TLS overlay TOML from a merged li-httpd HTTP profile."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

CERT_DIR = "/var/lib/li-httpd/tls/homelab"
LISTEN_HTTPS = "0.0.0.0:443"


def _toml_quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _write_inline_table(name: str, table: dict[str, Any]) -> list[str]:
    lines = [f"[{name}]"]
    for key, val in table.items():
        if isinstance(val, bool):
            lines.append(f"{key} = {'true' if val else 'false'}")
        elif isinstance(val, (int, float)):
            lines.append(f"{key} = {val}")
        elif isinstance(val, list):
            items = ", ".join(_toml_quote(str(v)) for v in val)
            lines.append(f"{key} = [{items}]")
        else:
            lines.append(f"{key} = {_toml_quote(str(val))}")
    return lines


def build_overlay(http: dict[str, Any]) -> dict[str, Any]:
    server_in = http.get("server") if isinstance(http.get("server"), dict) else {}
    root = server_in.get("document_root", "/var/lib/li-httpd/empty")

    overlay: dict[str, Any] = {
        "server": {
            "listen": LISTEN_HTTPS,
            "document_root": str(root),
            "tls": {
                "mode": "self_signed",
                "cert_dir": CERT_DIR,
                "min_protocol": "1.2",
                "terminate": True,
                "self_signed": {"dev": True, "valid_days": 365},
            },
        },
    }

    for key in ("health", "limits", "auth"):
        if key in http:
            overlay[key] = copy.deepcopy(http[key])

    if isinstance(http.get("upstreams"), dict):
        overlay["upstreams"] = copy.deepcopy(http["upstreams"])

    sites_out: list[dict[str, Any]] = []
    for site in http.get("site") or []:
        if not isinstance(site, dict):
            continue
        s = copy.deepcopy(site)
        s["listen"] = LISTEN_HTTPS
        sites_out.append(s)
    overlay["site"] = sites_out
    return overlay


def write_toml(data: dict[str, Any]) -> str:
    lines: list[str] = []

    server = data.get("server") or {}
    if isinstance(server, dict):
        lines.extend(_write_inline_table("server", {k: v for k, v in server.items() if k != "tls"}))
        lines.append("")
        tls = server.get("tls")
        if isinstance(tls, dict):
            tls_flat: dict[str, Any] = {}
            ss: dict[str, Any] = {}
            for k, v in tls.items():
                if k == "self_signed" and isinstance(v, dict):
                    ss = v
                else:
                    tls_flat[k] = v
            lines.extend(_write_inline_table("server.tls", tls_flat))
            if ss:
                lines.append("")
                lines.extend(_write_inline_table("server.tls.self_signed", ss))
        lines.append("")

    for key in ("health", "limits", "auth"):
        if key in data and isinstance(data[key], dict):
            lines.extend(_write_inline_table(key, data[key]))
            lines.append("")

    upstreams = data.get("upstreams") or {}
    if isinstance(upstreams, dict):
        for pool_id in sorted(upstreams):
            spec = upstreams[pool_id]
            if isinstance(spec, dict):
                lines.extend(_write_inline_table(f"upstreams.{pool_id}", spec))
                lines.append("")

    for site in data.get("site") or []:
        if not isinstance(site, dict):
            continue
        lines.append("[[site]]")
        if site.get("host") is not None:
            lines.append(f"host = {_toml_quote(str(site['host']))}")
        if site.get("listen") is not None:
            lines.append(f"listen = {_toml_quote(str(site['listen']))}")
        limits = site.get("limits")
        if isinstance(limits, dict):
            lines.append("")
            lines.extend(_write_inline_table("site.limits", limits))
        routes = site.get("routes")
        if isinstance(routes, dict):
            lines.append("")
            lines.append("[site.routes]")
            for rk, rv in routes.items():
                lines.append(f"{_toml_quote(str(rk))} = {_toml_quote(str(rv))}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate HTTPS overlay TOML from merged HTTP profile")
    ap.add_argument("input", type=Path, help="merged homelab HTTP TOML")
    ap.add_argument("-o", "--output", type=Path, required=True)
    args = ap.parse_args()

    if not args.input.is_file():
        print(f"gen-https-overlay: missing {args.input}", file=sys.stderr)
        return 1

    data = tomllib.loads(args.input.read_text(encoding="utf-8"))
    overlay = build_overlay(data)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(write_toml(overlay), encoding="utf-8")
    print(f"gen-https-overlay: wrote {args.output} ({len(overlay.get('site') or [])} sites)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

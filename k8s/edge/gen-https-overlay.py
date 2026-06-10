#!/usr/bin/env python3
"""Build a :443 + TLS overlay TOML from a merged li-httpd HTTP profile."""

from __future__ import annotations

import argparse
import copy
import os
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

CERT_DIR = "/var/lib/li-httpd/tls/homelab"
LETSENCRYPT_LIVE = "/etc/letsencrypt/live/majico.d3bu7.com"
GITLAB_TLS_LIVE = Path("/etc/letsencrypt/live/gitlab.lilangverse.xyz")
HOMELAB_EDGE_TLS_LIVE = os.environ.get(
    "HOMELAB_EDGE_TLS_LIVE", "/etc/letsencrypt/live/homelab-edge"
).strip()
HOMELAB_EDGE_TLS_LIVE = os.environ.get(
    "HOMELAB_EDGE_TLS_LIVE", "/etc/letsencrypt/live/homelab-edge"
).strip()
# Production GitLab HTTPS is nginx :443; li-httpd TLS overlay uses :8443 for dev/benchmark.
_LISTEN_RAW = os.environ.get("HOMELAB_LI_HTTPD_TLS_PORT", ":8443").strip()
LISTEN_HTTPS = _LISTEN_RAW if _LISTEN_RAW.startswith(":") else f":{_LISTEN_RAW}"
ACME_EMAIL = os.environ.get("HOMELAB_ACME_EMAIL", "admin@majico.xyz").strip()

WAN_TLS_SUFFIXES = (".klaut.pro", ".d3bu7.com", ".lilangverse.xyz", ".obsevia.com")


def _wan_site_hosts(http: dict[str, Any]) -> list[str]:
    hosts: list[str] = []
    for site in http.get("site") or []:
        if not isinstance(site, dict):
            continue
        host = str(site.get("host", "")).strip().lower()
        if not host or host.endswith(".homelab.lan"):
            continue
        if any(host.endswith(suffix) for suffix in WAN_TLS_SUFFIXES):
            hosts.append(host)
    return sorted(set(hosts))


def _cert_sans(cert_path: Path) -> set[str]:
    import subprocess

    try:
        proc = subprocess.run(
            ["openssl", "x509", "-in", str(cert_path), "-noout", "-ext", "subjectAltName"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return set()
    sans: set[str] = set()
    for token in proc.stdout.replace("DNS:", " ").replace(",", " ").split():
        name = token.strip().lower()
        if name and name not in {"subject", "alternativename", "name"} and not name.startswith("x509v3"):
            sans.add(name.lstrip("*."))
    return sans


ACME_DOMAINS = [
    d.strip()
    for d in os.environ.get(
        "HOMELAB_ACME_DOMAINS", "majico.d3bu7.com,api.majico.d3bu7.com,supabase.majico.d3bu7.com,search.klaut.pro,gitlab.klaut.pro,gitlab.lilangverse.xyz,registry.gitlab.lilangverse.xyz"
    ).split(",")
    if d.strip()
]


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



def _manual_tls_block(cert: Path, key: Path) -> dict[str, Any]:
    return {
        "mode": "manual",
        "cert_dir": CERT_DIR,
        "min_protocol": "1.3",
        "terminate": True,
        "manual": {"cert": str(cert), "key": str(key)},
    }


def _tls_block(http: dict[str, Any]) -> dict[str, Any]:
    """Prefer a LE cert on disk when it covers all WAN site hosts; else certbot + homelab-edge."""
    wan_hosts = _wan_site_hosts(http)
    acme_domains = sorted(set(ACME_DOMAINS) | set(wan_hosts))
    for live_dir in (Path(HOMELAB_EDGE_TLS_LIVE), Path(LETSENCRYPT_LIVE)):
        cert = live_dir / "fullchain.pem"
        key = live_dir / "privkey.pem"
        if cert.is_file() and key.is_file():
            sans = _cert_sans(cert)
            if wan_hosts and sans and all(h in sans for h in wan_hosts):
                return _manual_tls_block(cert, key)
    lilang_hosts = [h for h in wan_hosts if h.endswith(".lilangverse.xyz")]
    g_cert = GITLAB_TLS_LIVE / "fullchain.pem"
    g_key = GITLAB_TLS_LIVE / "privkey.pem"
    if lilang_hosts and g_cert.is_file() and g_key.is_file():
        sans = _cert_sans(g_cert)
        if sans and all(h in sans for h in lilang_hosts):
            print(
                "gen-https-overlay: using gitlab.lilangverse.xyz LE cert "
                "(homelab-edge / full WAN cert not available)",
                file=sys.stderr,
            )
            return _manual_tls_block(g_cert, g_key)
    le_cert = Path(LETSENCRYPT_LIVE) / "fullchain.pem"
    le_key = Path(LETSENCRYPT_LIVE) / "privkey.pem"
    if le_cert.is_file() and le_key.is_file():
        print(
            "gen-https-overlay: warn: no LE cert covers all WAN hosts; "
            "using partial majico cert until homelab-edge is issued",
            file=sys.stderr,
        )
        return _manual_tls_block(le_cert, le_key)
    if ACME_EMAIL and acme_domains and os.environ.get("HOMELAB_ACME_VIA_OVERLAY") == "1":
        return {
            "mode": "lets_encrypt",
            "cert_dir": CERT_DIR,
            "min_protocol": "1.3",
            "terminate": True,
            "lets_encrypt": {
                "email": ACME_EMAIL,
                "domains": acme_domains,
                "environment": "production",
            },
        }
    return {
        "mode": "self_signed",
        "cert_dir": CERT_DIR,
        "min_protocol": "1.3",
        "terminate": True,
        "self_signed": {"dev": True, "valid_days": 365},
    }


def build_overlay(http: dict[str, Any]) -> dict[str, Any]:
    server_in = http.get("server") if isinstance(http.get("server"), dict) else {}
    root = server_in.get("document_root", "/var/lib/li-httpd/empty")

    overlay: dict[str, Any] = {
        "server": {
            "listen": LISTEN_HTTPS,
            "document_root": str(root),
            "tls": _tls_block(http),
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
            nested: dict[str, dict[str, Any]] = {}
            for k, v in tls.items():
                if k in ("self_signed", "manual", "lets_encrypt") and isinstance(v, dict):
                    nested[k] = v
                else:
                    tls_flat[k] = v
            lines.extend(_write_inline_table("server.tls", tls_flat))
            for sub_key in ("manual", "lets_encrypt", "self_signed"):
                if sub_key in nested:
                    lines.append("")
                    lines.extend(_write_inline_table(f"server.tls.{sub_key}", nested[sub_key]))
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

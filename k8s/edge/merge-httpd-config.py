#!/usr/bin/env python3
"""Merge multiple li-httpd TOML profiles into one file for flatten + li-httpd."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore


class MergeError(Exception):
    pass


def _site_host(site: dict[str, Any]) -> str:
    host = site.get("host")
    if not host:
        raise MergeError("[[site]] entry missing host")
    return str(host).strip()


def _upstream_entries(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = data.get("upstreams")
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise MergeError("[upstreams] must be a table")
    return {str(k): v for k, v in raw.items() if isinstance(v, dict)}


def _merge_upstreams(
    base: dict[str, dict[str, Any]], extra: dict[str, dict[str, Any]], src: Path
) -> None:
    for pool_id, spec in extra.items():
        if pool_id in base and base[pool_id] != spec:
            raise MergeError(f"conflicting upstreams.{pool_id} in {src}")
        base[pool_id] = spec


def _merge_sites(sites: list[dict[str, Any]], extra: list[Any], src: Path) -> None:
    seen = {_site_host(s) for s in sites if isinstance(s, dict)}
    for entry in extra:
        if not isinstance(entry, dict):
            raise MergeError(f"invalid [[site]] in {src}")
        host = _site_host(entry)
        if host in seen:
            raise MergeError(f"duplicate site host {host!r} ({src})")
        seen.add(host)
        sites.append(entry)


def merge_files(paths: list[Path]) -> dict[str, Any]:
    if not paths:
        raise MergeError("no input files")
    merged: dict[str, Any] = {}
    upstreams: dict[str, dict[str, Any]] = {}
    sites: list[dict[str, Any]] = []

    for path in paths:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        if not merged:
            for key in ("server", "health", "limits", "auth"):
                if key in data:
                    merged[key] = data[key]

        _merge_upstreams(upstreams, _upstream_entries(data), path)
        raw_sites = data.get("site")
        if raw_sites is not None:
            if not isinstance(raw_sites, list):
                raise MergeError(f"[site] must be array in {path}")
            _merge_sites(sites, raw_sites, path)

    if not merged.get("server"):
        raise MergeError("first file must define [server]")
    if upstreams:
        merged["upstreams"] = upstreams
    merged["site"] = sites
    return merged


def _toml_quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _write_scalar(key: str, val: Any, pad: str) -> str:
    if isinstance(val, bool):
        return f"{pad}{key} = {'true' if val else 'false'}"
    if isinstance(val, (int, float)):
        return f"{pad}{key} = {val}"
    return f"{pad}{key} = {_toml_quote(str(val))}"


def _write_inline_table(name: str, table: dict[str, Any]) -> list[str]:
    lines = [f"[{name}]"]
    for key, val in table.items():
        if isinstance(val, list):
            items = ", ".join(_toml_quote(str(v)) for v in val)
            lines.append(f"{key} = [{items}]")
        else:
            lines.append(_write_scalar(key, val, ""))
    return lines


def write_toml(data: dict[str, Any]) -> str:
    lines: list[str] = []
    for key in ("server", "health", "limits", "auth"):
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
            lines.append(_write_scalar("host", site["host"], ""))
        if site.get("listen") is not None:
            lines.append(_write_scalar("listen", site["listen"], ""))
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


def validate_merged(path: Path) -> None:
    candidates = []
    if os.environ.get("LIS_ROOT"):
        candidates.append(Path(os.environ["LIS_ROOT"]) / "scripts")
    if os.environ.get("LIC_ROOT"):
        candidates.append(Path(os.environ["LIC_ROOT"]) / "scripts")
    candidates.append(Path(__file__).resolve().parents[3] / "li" / "lis" / "scripts")

    for root in candidates:
        if (root / "httpd_config.py").is_file():
            sys.path.insert(0, str(root))
            from httpd_config import load_httpd_sites

            sites = load_httpd_sites(path)
            print(f"validate: OK ({len(sites)} sites)")
            return
    print("validate: skipped (set LIS_ROOT or LIC_ROOT for oracle check)")


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge li-httpd TOML profiles")
    ap.add_argument("inputs", nargs="+", type=Path, help="TOML files in merge order")
    ap.add_argument("-o", "--output", type=Path, required=True)
    ap.add_argument("--validate", action="store_true", help="run lis httpd_config oracle")
    args = ap.parse_args()

    try:
        merged = merge_files(args.inputs)
        text = write_toml(merged)
    except MergeError as e:
        print(f"merge error: {e}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text, encoding="utf-8")
    print(f"merge: wrote {args.output}")

    if args.validate:
        validate_merged(args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())

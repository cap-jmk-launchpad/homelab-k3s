#!/usr/bin/env python3
"""Deny agent actions that delete, move, or overwrite homelab SSH keys and local secrets."""

from __future__ import annotations

import json
import re
import sys

# Paths agents must never touch without explicit user action in a real terminal.
PROTECTED_PATH = re.compile(
    r"(?:"
    r"[/\\]\.ssh[/\\](?:homelab|beelink|blackpearl|id_ed25519|id_rsa)(?:\.pub)?|"
    r"[/\\]beelink-cleanup[/\\](?:homelab|beelink|blackpearl|\.env|\.kube[/\\]config-homelab)|"
    r"[/\\]homelab-k3s[/\\](?:homelab|beelink|blackpearl|\.env)|"
    r"[/\\]\.kube[/\\]config-homelab"
    r")",
    re.IGNORECASE,
)

DESTRUCTIVE_SHELL = re.compile(
    r"\b("
    r"rm|rmdir|del(?:ete)?|remove-item|erase|shred|unlink|"
    r"move-item|mv|ren(?:ame(?:-item)?)?|copy-item|cp\s|"
    r"set-content|out-file|clear-content|truncate"
    r")\b",
    re.IGNORECASE,
)

DENY = {
    "permission": "deny",
    "user_message": (
        "Blocked: Cursor agents must not delete, move, or overwrite SSH keys, "
        "kubeconfig, or .env. Run that yourself in a terminal if you really need it."
    ),
    "agent_message": (
        "Protected homelab secret path. Do not modify or remove local SSH keys, "
        "kubeconfig, or .env. Tell the user what to run manually."
    ),
}

ALLOW = {"permission": "allow"}


def _text(*parts: str) -> str:
    return " ".join(p for p in parts if p)


def _path_from_payload(data: dict) -> str:
    tool_input = data.get("tool_input") or {}
    if isinstance(tool_input, dict):
        for key in ("path", "target_file", "file_path", "contents_path"):
            value = tool_input.get(key)
            if isinstance(value, str):
                return value
    for key in ("path", "file_path"):
        value = data.get(key)
        if isinstance(value, str):
            return value
    return ""


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(json.dumps(ALLOW))
        return 0

    command = str(data.get("command") or "")
    tool_name = str(data.get("tool_name") or data.get("tool") or "")
    path = _path_from_payload(data)
    blob = _text(command, path, json.dumps(data.get("tool_input") or {}))

    if PROTECTED_PATH.search(blob):
        if tool_name in {"Delete", "Write"}:
            print(json.dumps(DENY))
            return 0
        if command and DESTRUCTIVE_SHELL.search(command):
            print(json.dumps(DENY))
            return 0

    print(json.dumps(ALLOW))
    return 0


if __name__ == "__main__":
    sys.exit(main())

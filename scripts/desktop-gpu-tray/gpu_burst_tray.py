#!/usr/bin/env python3
"""Windows system tray toggle for desktop GPU burst mode (homelab k3s)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
from pathlib import Path

import pystray
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[2]
SSH_KEY = os.environ.get("HOMELAB_SSH_KEY", str(REPO_ROOT / "homelab"))
SSH_HOST = os.environ.get("HOMELAB_SSH_HOST", "s4il0r@192.168.10.41")
REMOTE_SCRIPTS = os.environ.get(
    "HOMELAB_GPU_SCRIPTS", "~/homelab-k3s/scripts"
)

MODE_BURST = "burst"
MODE_GAMING = "gaming"
MODE_UNKNOWN = "unknown"

MODE_LABELS = {
    MODE_BURST: "Cluster burst (share GPU)",
    MODE_GAMING: "Gaming (GPU for me)",
    MODE_UNKNOWN: "Status unknown",
}


class GpuBurstTray:
    def __init__(self) -> None:
        self.mode = MODE_UNKNOWN
        self.last_error: str | None = None
        self._busy = False
        self._icons = {
            MODE_BURST: self._make_icon((46, 125, 50)),
            MODE_GAMING: self._make_icon((41, 98, 168)),
            MODE_UNKNOWN: self._make_icon((120, 120, 120)),
        }
        self.icon = pystray.Icon(
            "desktop-gpu-burst",
            self._icons[MODE_UNKNOWN],
            MODE_LABELS[MODE_UNKNOWN],
            menu=pystray.Menu(
                pystray.MenuItem(
                    "Gaming mode (GPU for me)",
                    self._gaming_mode,
                    checked=lambda _: self.mode == MODE_GAMING,
                    radio=True,
                ),
                pystray.MenuItem(
                    "Cluster burst (share GPU)",
                    self._burst_mode,
                    checked=lambda _: self.mode == MODE_BURST,
                    radio=True,
                ),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Refresh status", self._refresh),
                pystray.MenuItem("Quit", self._quit),
            ),
        )

    @staticmethod
    def _make_icon(rgb: tuple[int, int, int]) -> Image.Image:
        size = 64
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.ellipse((4, 4, size - 4, size - 4), fill=(*rgb, 255))
        draw.ellipse((18, 18, size - 18, size - 18), fill=(255, 255, 255, 220))
        return image

    def _ssh(self, remote_cmd: str, timeout: int = 45) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                "-i",
                SSH_KEY,
                SSH_HOST,
                remote_cmd,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def _parse_mode(self, payload: str) -> str:
        data = json.loads(payload)
        labels = data.get("metadata", {}).get("labels", {})
        taints = data.get("spec", {}).get("taints") or []
        burst_enabled = labels.get("burst") == "enabled"
        has_burst_taint = any(
            t.get("key") == "workload" and t.get("value") == "burst" for t in taints
        )
        if burst_enabled and not has_burst_taint:
            return MODE_BURST
        if has_burst_taint or not burst_enabled:
            return MODE_GAMING
        return MODE_UNKNOWN

    def _fetch_mode(self) -> tuple[str, str | None]:
        if not Path(SSH_KEY).is_file():
            return MODE_UNKNOWN, f"SSH key not found: {SSH_KEY}"

        result = self._ssh("kubectl get node desktop -o json")
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "kubectl failed").strip()
            return MODE_UNKNOWN, detail

        try:
            return self._parse_mode(result.stdout), None
        except json.JSONDecodeError as exc:
            return MODE_UNKNOWN, f"Invalid kubectl JSON: {exc}"

    def _apply_ui(self) -> None:
        title = MODE_LABELS[self.mode]
        if self.last_error:
            short = self.last_error.replace("\n", " ").strip()
            if len(short) > 80:
                short = short[:77] + "..."
            title = f"{title} — {short}"
        self.icon.icon = self._icons[self.mode]
        self.icon.title = title

    def _refresh(self, _icon: pystray.Icon | None = None, _item=None) -> None:
        if self._busy:
            return
        self._run_async(self._refresh_worker)

    def _refresh_worker(self) -> None:
        mode, error = self._fetch_mode()
        self.mode = mode
        self.last_error = error
        self._apply_ui()

    def _gaming_mode(self, _icon: pystray.Icon, _item) -> None:
        if self._busy or self.mode == MODE_GAMING:
            return
        self._run_async(lambda: self._set_mode_worker("off"))

    def _burst_mode(self, _icon: pystray.Icon, _item) -> None:
        if self._busy or self.mode == MODE_BURST:
            return
        self._run_async(lambda: self._set_mode_worker("on"))

    def _set_mode_worker(self, action: str) -> None:
        script = (
            f"{REMOTE_SCRIPTS}/desktop-gpu-burst-on.sh"
            if action == "on"
            else f"{REMOTE_SCRIPTS}/desktop-gpu-burst-off.sh"
        )
        result = self._ssh(f"bash {script}", timeout=60)
        if result.returncode != 0:
            self.last_error = (result.stderr or result.stdout or "SSH script failed").strip()
            self.mode = MODE_UNKNOWN
        else:
            self.last_error = None
            self.mode = MODE_BURST if action == "on" else MODE_GAMING
        self._apply_ui()

    def _run_async(self, worker) -> None:
        self._busy = True

        def wrapped() -> None:
            try:
                worker()
            finally:
                self._busy = False

        threading.Thread(target=wrapped, daemon=True).start()

    def _quit(self, _icon: pystray.Icon, _item) -> None:
        self.icon.stop()

    def run(self) -> None:
        self._refresh_worker()
        self.icon.run()


def main() -> int:
    if sys.platform != "win32":
        print("This tray app is intended for Windows.", file=sys.stderr)
        return 1
    GpuBurstTray().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

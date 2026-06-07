#!/usr/bin/env python3
"""Compare Prometheus filesystem metrics vs actual mounts per node."""
import json
import subprocess

NODES = {
    "anch0r": "192.168.10.22",
    "blackpearl": "192.168.10.33",
    "deck": "192.168.10.26",
    "desktop": "192.168.10.31",
    "engine": "192.168.10.32",
}

FS_FILTER = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat|ntfs|fuseblk",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/host"'
)


def prom_query(q):
    prom = subprocess.check_output(
        [
            "kubectl", "get", "pod", "-n", "monitoring",
            "prometheus-prometheus-stack-prometheus-0",
            "-o", "jsonpath={.status.podIP}",
        ],
        text=True,
    ).strip()
    out = subprocess.check_output(
        ["curl", "-sfG", f"http://{prom}:9090/api/v1/query", "--data-urlencode", f"query={q}"],
        text=True,
    )
    return json.loads(out)["data"]["result"]


def host_df(node: str) -> list[tuple[str, str, str, float]]:
    cmd = [
        "kubectl", "debug", f"node/{node}", "--image=busybox:1.36",
        "--profile=general", "--quiet", "--",
        "chroot", "/host", "sh", "-c",
        "df -hT --output=source,fstype,target,size 2>/dev/null | tail -n +2",
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=45)
    except subprocess.CalledProcessError as e:
        return [("error", "", e.output or str(e), 0.0)]
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        src, fstype, target = parts[0], parts[1], parts[2]
        size = parts[3]
        rows.append((src, fstype, target, size))
    return rows


def parse_size_gib(s: str) -> float:
    s = s.strip()
    if s.endswith("T"):
        return float(s[:-1]) * 1024
    if s.endswith("G"):
        return float(s[:-1])
    if s.endswith("M"):
        return float(s[:-1]) / 1024
    if s.endswith("K"):
        return float(s[:-1]) / 1024 / 1024
    return 0.0


print("=== Prometheus: all mountpoints >= 1 GiB (any fstype, before dashboard filters) ===")
q = 'node_filesystem_size_bytes / 1024^3'
by_node: dict[str, list] = {ip: [] for ip in NODES.values()}
for r in prom_query(q):
    m = r["metric"]
    inst = m.get("instance", "?")
    gb = float(r["value"][1])
    if gb < 1:
        continue
    mp = m.get("mountpoint", "?")
    if mp.startswith("/var/lib/kubelet") or mp.startswith("/run/k3s"):
        continue
    by_node.setdefault(inst, []).append((mp, m.get("device", "?"), m.get("fstype", "?"), gb))

for name, ip in NODES.items():
    inst = f"{ip}:9100"
    rows = sorted(by_node.get(inst, []), key=lambda x: -x[3])
    total = sum(x[3] for x in rows)
    print(f"\n{name} ({inst}) — {total:.1f} GiB in metrics ({len(rows)} mounts)")
    if not rows:
        print("  (no filesystem metrics)")
    for mp, dev, fst, gb in rows[:15]:
        print(f"  {gb:7.1f} GiB  {fst:8}  {mp:30}  {dev}")

print("\n=== Host df (actual mounts on node) ===")
host_totals = {}
for name in NODES:
    print(f"\n--- {name} ---")
    rows = host_df(name)
    total = 0.0
    for src, fstype, target, size in rows:
        if target.startswith("/var/lib/kubelet") or target.startswith("/run/k3s"):
            continue
        if target.startswith("/boot"):
            continue
        gib = parse_size_gib(size)
        if gib < 1:
            continue
        total += gib
        print(f"  {size:>8}  {fstype:8}  {target:30}  {src}")
    host_totals[name] = total
    print(f"  >> host total (>=1G mounts, rough): {total:.1f} GiB")

print("\n=== Summary ===")
prom_total = sum(sum(x[3] for x in by_node.get(f"{ip}:9100", [])) for ip in NODES.values())
host_total = sum(host_totals.values())
print(f"Prometheus sum (all nodes, >=1G): {prom_total:.1f} GiB")
print(f"Host df sum (all nodes, >=1G):    {host_total:.1f} GiB")
print("\nNodes missing from Prometheus metrics:")
for name, ip in NODES.items():
    inst = f"{ip}:9100"
    if not by_node.get(inst):
        print(f"  {name} — up check: ", end="")
        up = prom_query(f'up{{job="node-exporter",instance="{inst}"}}')
        print(up[0]["value"][1] if up else "?")

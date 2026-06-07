#!/usr/bin/env python3
import json, subprocess

NODES = [
    ("anch0r", "192.168.10.22"),
    ("deck", "192.168.10.26"),
    ("blackpearl", "192.168.10.33"),
]

def prom_query(q):
    prom = subprocess.check_output(
        ["kubectl", "get", "pod", "-n", "monitoring", "prometheus-prometheus-stack-prometheus-0",
         "-o", "jsonpath={.status.podIP}"], text=True).strip()
    out = subprocess.check_output(
        ["curl", "-sfG", f"http://{prom}:9090/api/v1/query", "--data-urlencode", f"query={q}"],
        text=True)
    return json.loads(out)["data"]["result"]

print("=== All filesystem metrics >= 0.5 GiB (any fstype) ===")
for name, ip in NODES:
    inst = f"{ip}:9100"
    print(f"\n{name} ({inst})")
    q = f'node_filesystem_size_bytes{{instance="{inst}"}} / 1024^3'
    rows = []
    for r in prom_query(q):
        m = r["metric"]
        gb = float(r["value"][1])
        if gb < 0.5:
            continue
        err = m.get("device_error", "")
        rows.append((gb, m.get("fstype"), m.get("mountpoint"), m.get("device"), err))
    if not rows:
        print("  (none)")
    for gb, fst, mp, dev, err in sorted(rows, key=lambda x: -x[0]):
        flag = " ERR" if err else ""
        print(f"  {gb:7.1f} GiB  {fst:10}  {mp:35}  {dev}{flag}")

print("\n=== Dashboard filter (ext4|xfs|btrfs|ext2|vfat only) ===")
FS = 'fstype=~"ext4|xfs|btrfs|ext2|vfat",mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/mnt/c|/mnt/e|/host|/var/lib/docker.*|/run/k3s.*"'
q = f"sum(max by (instance, device) (node_filesystem_size_bytes{{{FS}}})) / 1024^3"
for r in prom_query(q):
    print(f"  {r['metric'].get('instance','?'):22} {float(r['value'][1]):.1f} GiB")

print("\n=== Host lsblk (debug pods) ===")
for name in ["anch0r", "deck", "blackpearl"]:
    subprocess.run([
        "kubectl", "debug", f"node/{name}", "--image=busybox:1.36", "--profile=general", "--quiet", "--",
        "chroot", "/host", "sh", "-c",
        "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS; echo; df -hT -x tmpfs -x devtmpfs 2>/dev/null | head -15; echo; command -v zpool >/dev/null && zpool list || echo no-zpool"
    ], check=False)

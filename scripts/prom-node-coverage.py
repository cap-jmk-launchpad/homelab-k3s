#!/usr/bin/env python3
"""Check node-exporter coverage and disk metrics (run on blackpearl)."""
import json
import subprocess

def prom_query(q):
    prom = subprocess.check_output(
        ["kubectl", "get", "pod", "-n", "monitoring", "prometheus-prometheus-stack-prometheus-0",
         "-o", "jsonpath={.status.podIP}"], text=True).strip()
    out = subprocess.check_output(
        ["curl", "-sfG", f"http://{prom}:9090/api/v1/query", "--data-urlencode", f"query={q}"],
        text=True)
    return json.loads(out)["data"]["result"]

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/mnt/c|/mnt/e|/host|/var/lib/docker.*|/run/k3s.*"'
)

print("=== node-exporter pods ===")
subprocess.run(["kubectl", "get", "pods", "-n", "monitoring",
                "-l", "app.kubernetes.io/name=prometheus-node-exporter", "-o", "wide"], check=False)

print("\n=== up{job=node-exporter} ===")
for r in sorted(prom_query('up{job="node-exporter"}'), key=lambda x: x["metric"].get("instance", "")):
    m = r["metric"]
    print(f"  {m.get('instance','?'):22} up={r['value'][1]} node={m.get('node','?')}")

print("\n=== kube nodes ===")
subprocess.run(["kubectl", "get", "nodes", "-o", "custom-columns=NAME:.metadata.name,IP:.status.addresses[0].address"],
                 check=False)

print("\n=== Disk GiB by instance (deduped devices) ===")
q = f"sum by (instance, device) (max by (instance, device, mountpoint) (node_filesystem_size_bytes{{{FS}}})) / 1024^3"
by_inst = {}
for r in prom_query(q):
    inst = r["metric"]["instance"]
    dev = r["metric"]["device"]
    gb = float(r["value"][1])
    if gb < 0.5:
        continue
    by_inst.setdefault(inst, []).append((dev, gb))

total = 0.0
for inst in sorted(by_inst):
    s = sum(g for _, g in by_inst[inst])
    total += s
    print(f"\n{inst}  ({s:.1f} GiB)")
    for dev, gb in sorted(by_inst[inst], key=lambda x: -x[1]):
        print(f"  {dev:18} {gb:8.1f} GiB")
print(f"\nCluster mounted total: {total:.1f} GiB")

print("\n=== Prometheus scrape targets (down) ===")
for r in prom_query('up==0'):
    m = r["metric"]
    print(f"  {m.get('job','?')} {m.get('instance','?')} {m.get('node', m.get('kubernetes_node',''))}")

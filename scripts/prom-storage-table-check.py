#!/usr/bin/env python3
import json, subprocess

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/mnt/c|/mnt/e|/host|/var/lib/docker.*|/run/k3s.*"'
)

def prom_query(q):
    prom = subprocess.check_output(
        ["kubectl", "get", "pod", "-n", "monitoring", "prometheus-prometheus-stack-prometheus-0",
         "-o", "jsonpath={.status.podIP}"], text=True).strip()
    out = subprocess.check_output(
        ["curl", "-sfG", f"http://{prom}:9090/api/v1/query", "--data-urlencode", f"query={q}"],
        text=True)
    return json.loads(out)["data"]["result"]

print("=== kube_node_info (node, internal_ip) ===")
for r in prom_query("kube_node_info"):
    m = r["metric"]
    print(f"  {m.get('node','?'):12} internal_ip={m.get('internal_ip','?')}")

print("\n=== up{job=node-exporter} instance ===")
for r in sorted(prom_query('up{job="node-exporter"}'), key=lambda x: x["metric"].get("instance","")):
    print(f"  {r['metric'].get('instance','?'):22} up={r['value'][1]}")

JOIN = (
    '* on(instance) group_left(node) label_replace(kube_node_info, '
    '"instance", "$1:9100", "internal_ip", "(.*)")'
)
node_q = f"(sum by (instance) (max by (instance, device) (node_filesystem_size_bytes{{{FS}}})) / 1024^3) {JOIN}"
print("\n=== Per-node disk (Grafana storage table query) ===")
for r in sorted(prom_query(node_q), key=lambda x: x["metric"].get("node","")):
    m = r["metric"]
    print(f"  {m.get('node','?'):12} {m.get('instance','?'):22} {float(r['value'][1]):.1f} GiB")

cluster_q = f"sum(max by (instance, device) (node_filesystem_size_bytes{{{FS}}})) / 1024^3"
cluster = float(prom_query(cluster_q)[0]["value"][1])
print(f"\n=== Cluster total (panel 111): {cluster:.1f} GiB ===")

missing = []
for r in prom_query("kube_node_info"):
    node = r["metric"]["node"]
    ip = r["metric"].get("internal_ip", "")
    inst = f"{ip}:9100"
    disk = [x for x in prom_query(node_q) if x["metric"].get("node") == node]
    if not disk:
        missing.append(f"{node} (internal_ip={ip}, expected instance={inst})")
if missing:
    print("\n=== Nodes MISSING from storage table join ===")
    for m in missing:
        print(f"  {m}")
else:
    print("\nAll kube nodes present in storage table join.")

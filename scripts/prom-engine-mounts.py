#!/usr/bin/env python3
import json, subprocess
# engine mountpoints from prometheus
prom = subprocess.check_output(["kubectl","get","pod","-n","monitoring","prometheus-prometheus-stack-prometheus-0","-o","jsonpath={.status.podIP}"], text=True).strip()
q = 'node_filesystem_size_bytes{instance="192.168.10.32:9100"}'
out = subprocess.check_output(["curl","-sfG",f"http://{prom}:9090/api/v1/query","--data-urlencode",f"query={q}"], text=True)
for r in json.loads(out)["data"]["result"]:
    m, gb = r["metric"], float(r["value"][1])/1024**3
    if gb >= 0.1:
        print(f"{m.get('mountpoint','?'):35} {m.get('device','?'):15} {m.get('fstype','?'):8} {gb:7.1f} GiB")
print("\nPod volumeMounts:")
pod = json.loads(subprocess.check_output(["kubectl","get","pod","-n","monitoring","-l","app.kubernetes.io/name=prometheus-node-exporter","-o","json"], text=True))
for p in pod["items"]:
    if p["spec"].get("nodeName") != "engine":
        continue
    for vm in p["spec"]["containers"][0].get("volumeMounts", []):
        print(f"  {vm['name']} -> {vm['mountPath']}")

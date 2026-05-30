# metrics-server (k3s)

The cluster ships **metrics-server** in `kube-system` (k3s default). It powers `kubectl top` and Lens resource columns.

If worker nodes show `<unknown>` in `kubectl top nodes`, patch the deployment for k3s self-signed kubelet certs:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'
```

Homelab install does not duplicate metrics-server into `monitoring`; only the patch above when needed.

Pin the deployment to the control plane so it can scrape all kubelets (avoid scheduling on `engine`):

```bash
kubectl apply -f metrics-server-patch.json   # see metrics-server-patch.json
kubectl apply -f metrics-server-pin-control-plane.yaml
```

## Worker firewall (9100 / 10250)

`metrics-server` and Prometheus node-exporter reach kubelets and exporters on **192.168.10.x**. Pi workers with **ufw** default-deny need:

```bash
# on each worker (anch0r, deck, …) as root
./homelab-open-monitoring-ports.sh
```

Or apply [homelab-worker-firewall-ds.yaml](./homelab-worker-firewall-ds.yaml) once, then delete the DaemonSet. See [docs/homelab-monitoring.md](../../docs/homelab-monitoring.md).

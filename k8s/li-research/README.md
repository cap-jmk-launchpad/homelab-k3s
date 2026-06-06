# li-research — homelab k8s

Warm index bulk storage on **engine** external HDD (`/dev/sdb1` → `/srv/homelab/external`).

## Apply

```bash
kubectl apply -f k8s/li-research/namespace.yaml
kubectl apply -f k8s/li-research/storage-class.yaml
kubectl apply -f k8s/li-research/pv-warm-index.yaml
kubectl apply -f k8s/li-research/pvc-warm-index.yaml
```

Verify: `kubectl -n li-research get pvc li-research-warm-index` → **Bound**

Host path: `/srv/homelab/external/li-research/warm-index` (250 Gi PV on Toshiba ~870 Gi free).

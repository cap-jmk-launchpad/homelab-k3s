# li-research — homelab k8s

Warm index on **engine** second Intenso (`sdc`, label `intenso-research`).  
First Intenso (`sdb`, `homelab-external`) is reserved for **lip-registry**.

## Apply

```bash
kubectl apply -f k8s/li-research/namespace.yaml
kubectl apply -f k8s/li-research/storage-class.yaml
kubectl apply -f k8s/li-research/pv-warm-index.yaml
kubectl apply -f k8s/li-research/pvc-warm-index.yaml
```

Host path: `/srv/homelab/intenso-research/li-research/warm-index` (250 Gi PV, ~916 Gi disk).

# Edge ingress

Many homelabs expose services with a **dedicated edge node** (or the control plane) that accepts LAN HTTP(S) and forwards to an in-cluster ingress controller.

This doc describes a common pattern: **router `:80` → edge host → Kubernetes ingress**.

Placeholders:

| Placeholder | Description |
|-------------|-------------|
| `<edge-host>` | Hostname of the edge/LB machine |
| `<lan-ip>` | Edge host LAN address |
| `<control-plane-host>` | k3s API / optional co-located ingress |

## Topology

```
Internet (optional)
       │
   [Router]
       │ :80 / :443
       ▼
  <edge-host>  ──►  reverse proxy (nginx, caddy, haproxy)
       │
       ▼
  Ingress Controller (NodePort or hostNetwork in cluster)
       │
       ▼
  Services / Pods
```

## Router configuration

1. DHCP reservation for `<edge-host>` → fixed `<lan-ip>`.
2. Port forward **TCP 80** (and **443** if terminating TLS on edge) to `<lan-ip>`.
3. For purely local DNS, point `*.home.example` or individual names to `<lan-ip>` via router DNS or `/etc/hosts`.

## Edge reverse proxy

Install nginx, Caddy, or similar on `<edge-host>`. Example nginx site (HTTP only on LAN):

```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://<ingress-backend-ip>:<ingress-port>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

`<ingress-backend-ip>` is typically:

- Node IP of a worker running ingress with `hostNetwork`, or
- NodePort on any node (e.g. `http://<lan-ip>:30080`), or
- MetalLB / kube-vip virtual IP if you run those

## In-cluster ingress

Install an ingress controller on k3s (Traefik was disabled at install — see [k3s-server.md](k3s-server.md)). Example Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - host: app.home.example
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-service
                port:
                  number: 80
```

## TLS options

| Approach | Notes |
|----------|-------|
| TLS on edge | Let's Encrypt or internal CA on `<edge-host>`; proxy HTTP to cluster |
| TLS in cluster | cert-manager + ingress TLS; edge passes through or terminates |
| LAN only | HTTP on `:80` is often enough for homelab |

## Firewall on edge

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow OpenSSH
```

Do **not** expose k3s API (6443) to the internet unless you know the risk; keep it LAN-only.

## Health checks

From a LAN client:

```bash
curl -H 'Host: app.home.example' http://<lan-ip>/
kubectl get ingress -A
```

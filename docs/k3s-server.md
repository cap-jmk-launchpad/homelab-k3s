# k3s control plane (single server)

One **k3s server** node runs the Kubernetes API and embedded datastore. Workers join as agents.

Placeholders:

| Placeholder | Description |
|-------------|-------------|
| `<control-plane-host>` | Hostname or `<lan-ip>` of the server |
| `<admin-user>` | Automation user from [node-prep.md](node-prep.md) |

## Prerequisites

- [Node prep](node-prep.md) completed on the control plane host
- Stable LAN IP (DHCP reservation recommended)
- Port **6443/tcp** reachable from worker subnets

## Install k3s server

On the control plane, as root or via sudo:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --tls-san <control-plane-host> \
  --tls-san <lan-ip>" sh -
```

Why disable Traefik: run your own ingress controller (nginx, traefik, etc.) or terminate HTTP on a dedicated edge node — see [edge-ingress.md](edge-ingress.md).

## Firewall

```bash
sudo ufw allow 6443/tcp comment 'k3s API for agents'
sudo ufw status
```

## Retrieve join token

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Save this securely. Workers need:

- `K3S_URL=https://<control-plane-host>:6443` (or `https://<lan-ip>:6443`)
- `K3S_TOKEN=<token from above>`

## kubeconfig

k3s writes admin kubeconfig for root:

```bash
sudo kubectl get nodes
```

Copy to your workstation (optional):

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

Replace `127.0.0.1` with `<lan-ip>` or `<control-plane-host>` in the `server:` field.

## Install ingress controller (in-cluster)

Example: ingress-nginx (adjust to your preference):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml
```

Wait for the controller pod, then expose via NodePort, LoadBalancer, or an external edge — [edge-ingress.md](edge-ingress.md).

## Upgrade k3s

Pin the same version across server and agents. Check [k3s releases](https://github.com/k3s-io/k3s/releases), then on the server:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=vX.Y.Z+k3sN sh -
```

Upgrade workers after the control plane is healthy.

## Uninstall (destructive)

```bash
/usr/local/bin/k3s-uninstall.sh
```

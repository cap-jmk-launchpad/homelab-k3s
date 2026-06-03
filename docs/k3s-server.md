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

Why disable Traefik: this homelab terminates HTTP on **blackpearl** with **li-httpd** (LIS edge TOML -> NodePort backends). See [edge-ingress.md](edge-ingress.md) and [k8s/edge/README.md](../k8s/edge/README.md).

## Firewall

```bash
sudo ufw allow 6443/tcp comment 'k3s API for agents'
sudo ufw status
```

On **blackpearl**, use [scripts/homelab-security-ufw-blackpearl-k3s.sh](../scripts/homelab-security-ufw-blackpearl-k3s.sh) (`ufw default allow routed` + flannel/cni0 rules). Plain `deny (routed)` breaks ClusterIP (`10.43.0.1` → `no route to host`).

## blackpearl: stable InternalIP vs DHCP

k3s registers `InternalIP` from install time (often `192.168.10.33`). If DHCP moves the host to another address (e.g. `.41`), kube-proxy still DNATs `kubernetes` to `.33:6443` and **ClusterIP breaks** until `.33` exists on the NIC:

```bash
sudo bash scripts/homelab-blackpearl-node-ip-fix.sh
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

## Edge ingress (LIS / li-httpd)

No in-cluster ingress controller. Workloads use **NodePort** or ClusterIP; **li-httpd** on the control plane proxies by hostname — [k8s/edge/README.md](../k8s/edge/README.md):

```bash
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh --install-systemd
```

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

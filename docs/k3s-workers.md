# k3s workers

Workers run the **k3s agent** and register with the control plane API on port 6443.

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `K3S_URL` | yes | e.g. `https://<control-plane-host>:6443` |
| `K3S_TOKEN` | yes | From control plane: `sudo cat /var/lib/rancher/k3s/server/node-token` |
| `NODE_NAME` | recommended | Kubernetes node name (defaults to short hostname) |
| NODE_IP | sometimes | LAN IP for multi-homed or WSL mirrored networking |
| MAX_PODS | optional | Kubelet pod cap (default 110). Use 250 on dense workers with a /24 PodCIDR; writes /etc/rancher/k3s/config.yaml before install |

## Native Linux worker

After [node-prep.md](node-prep.md):

```bash
sudo K3S_URL=https://<control-plane-host>:6443 \
  K3S_TOKEN=<token> \
  NODE_NAME=<node-name> \
  NODE_IP=<lan-ip> \
  bash scripts/join-k3s-agent.sh
```

Label from control plane:

```bash
kubectl label node <node-name> workload=general --overwrite
```

## Join from control plane (remote)

When SSH from control plane to worker is already configured with the homelab key:

```bash
WORKER_HOST=<admin-user>@<lan-ip> \
  NODE_NAME=<node-name> \
  bash scripts/join-from-control-plane.sh
```

WSL workers often use a non-default SSH port â€” see below.

## WSL2 worker (Ubuntu)

WSL2 can act as a burst worker with **mirrored networking** so the distro gets a real LAN address.

### One-time WSL setup

1. Install **Ubuntu** (e.g. 24.04) WSL distro.
2. Enable systemd in `/etc/wsl.conf`:

   ```ini
   [boot]
   systemd=true

   [user]
   default=<admin-user>
   ```

3. On Windows, `%USERPROFILE%\.wslconfig`:

   ```ini
   [wsl2]
   networkingMode=mirrored
   ```

4. Restart WSL: `wsl --shutdown`, then open Ubuntu.
5. Complete [node-prep.md](node-prep.md) inside WSL.
6. Run OpenSSH in WSL on a **dedicated port** (e.g. **2222**) if Windows already uses port 22.

Allow inbound on Windows (admin PowerShell, once):

```powershell
netsh advfirewall firewall add rule name="WSL Homelab SSH" dir=in action=allow protocol=TCP localport=2222
```

### Join WSL agent

Inside WSL as root:

```bash
sudo K3S_URL=https://<control-plane-host>:6443 \
  K3S_TOKEN=<token> \
  NODE_NAME=<node-name> \
  NODE_IP=<lan-ip> \
  bash scripts/join-k3s-agent.sh
```

From control plane with custom SSH port:

```bash
SSH_PORT=2222 WORKER_HOST=<admin-user>@<lan-ip> NODE_NAME=<node-name> \
  bash scripts/join-from-control-plane.sh
```

Verify:

```bash
kubectl get node <node-name> -o wide
sudo systemctl status k3s-agent   # inside WSL
```

Suggested labels: `workload=burst`, `machine=wsl2`.

## Raspberry Pi (arm64)

Same join flow on **arm64** Raspberry Pi OS or Ubuntu Server:

```bash
sudo K3S_URL=https://<control-plane-host>:6443 \
  K3S_TOKEN=<token> \
  NODE_NAME=<node-name> \
  bash scripts/join-k3s-agent.sh
```

Notes:

- Use a 64-bit OS for best k3s compatibility.
- Prefer wired Ethernet and a DHCP reservation for `<lan-ip>`.
- Pi 4/5 with sufficient RAM works for light workloads; avoid scheduling heavy jobs without taints/tolerations.

Label example: `workload=edge`, `machine=raspberry-pi`.


## Raise kubelet max-pods (existing agent)

Default kubelet capacity is **110 pods** per node. Dense workers (e.g. **engine**) can use `MAX_PODS=250` when joining, or on an already-joined host:

```bash
sudo MAX_PODS=250 bash scripts/k3s-write-kubelet-max-pods.sh
sudo systemctl restart k3s-agent
```

Verify from the control plane: `kubectl describe node <name>` should show `pods: 250` under Capacity/Allocatable.
## Re-join after failure

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh   # if present
# then run join again with fresh token if the server was reinstalled
```

## Scheduling

Use `nodeSelector` or affinity on labels you apply after join. Optional taints (e.g. `dedicated=training:NoSchedule`) keep burst/GPU nodes free until workloads tolerate them.

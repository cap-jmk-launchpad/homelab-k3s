#!/usr/bin/env bash
# Emergency: engine inbound LAN broken — reverse SSH tunnel GitLab to blackpearl :30581
set -euo pipefail

TUNNEL_PORT="${TUNNEL_PORT:-30581}"
KEY="${HOME}/.ssh/gitlab-tunnel-recovery"
NAMESPACE=gitlab

if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "gitlab-tunnel-recovery"
  grep -qF "$(cat "${KEY}.pub")" "${HOME}/.ssh/authorized_keys" || cat "${KEY}.pub" >>"${HOME}/.ssh/authorized_keys"
fi

PODIP="$(kubectl get pod -n "$NAMESPACE" gitlab-0 -o jsonpath='{.status.podIP}')"
echo "gitlab-0 pod IP: ${PODIP}"

kubectl delete secret gitlab-tunnel-ssh -n "$NAMESPACE" --ignore-not-found
kubectl create secret generic gitlab-tunnel-ssh -n "$NAMESPACE" --from-file=homelab="$KEY"

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gitlab-reverse-tunnel
  namespace: ${NAMESPACE}
  labels:
    app: gitlab-reverse-tunnel
spec:
  selector:
    matchLabels:
      app: gitlab-reverse-tunnel
  template:
    metadata:
      labels:
        app: gitlab-reverse-tunnel
    spec:
      nodeSelector:
        kubernetes.io/hostname: engine
      hostNetwork: true
      containers:
      - name: tunnel
        image: alpine:3.20
        command:
        - sh
        - -c
        - |
          set -eu
          apk add --no-cache openssh-client autossh >/dev/null
          cp /keys/homelab /tmp/homelab
          chmod 600 /tmp/homelab
          while true; do
            echo "tunnel: 127.0.0.1:${TUNNEL_PORT} -> ${PODIP}:80 via blackpearl"
            autossh -M 0 -N \\
              -o StrictHostKeyChecking=no \\
              -o UserKnownHostsFile=/dev/null \\
              -o ServerAliveInterval=15 \\
              -o ServerAliveCountMax=3 \\
              -o ExitOnForwardFailure=yes \\
              -i /tmp/homelab \\
              -R 127.0.0.1:${TUNNEL_PORT}:${PODIP}:80 \\
              s4il0r@192.168.10.33 || true
            sleep 5
          done
        volumeMounts:
        - name: ssh-key
          mountPath: /keys
          readOnly: true
      volumes:
      - name: ssh-key
        secret:
          secretName: gitlab-tunnel-ssh
          defaultMode: 0400
YAML

kubectl rollout status "daemonset/gitlab-reverse-tunnel" -n "$NAMESPACE" --timeout=90s
sleep 5
kubectl logs -n "$NAMESPACE" daemonset/gitlab-reverse-tunnel --tail=15

echo "=== tunnel probe ==="
curl -sS -o /dev/null -w "tunnel${TUNNEL_PORT}=%{http_code}\n" --max-time 20 \
  -H 'Host: gitlab.lilangverse.xyz' "http://127.0.0.1:${TUNNEL_PORT}/users/sign_in"

NGINX_CONF=/etc/nginx/gitlab-edge/nginx.conf
if grep -q "127.0.0.1:30481" "$NGINX_CONF" && ! grep -q "127.0.0.1:${TUNNEL_PORT}" "$NGINX_CONF"; then
  echo "=== patching nginx upstream to :${TUNNEL_PORT} ==="
  sudo sed -i "s|127.0.0.1:30481|127.0.0.1:${TUNNEL_PORT}|" "$NGINX_CONF"
  sudo nginx -t -c "$NGINX_CONF"
  sudo systemctl reload nginx-gitlab-edge.service
fi

curl -sk -o /dev/null -w "nginx443=%{http_code}\n" --max-time 20 \
  --resolve gitlab.lilangverse.xyz:443:127.0.0.1 \
  https://gitlab.lilangverse.xyz/users/sign_in

echo "recovery done (tunnel port ${TUNNEL_PORT})"

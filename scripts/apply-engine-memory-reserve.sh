#!/usr/bin/env bash
# Apply system-reserved memory on engine via privileged host pod (no SSH required).
set -euo pipefail

SYSTEM_RESERVED_MEMORY="${SYSTEM_RESERVED_MEMORY:-5Gi}"
KUBE_RESERVED_MEMORY="${KUBE_RESERVED_MEMORY:-512Mi}"
EVICTION_MEMORY="${EVICTION_MEMORY:-1Gi}"
NODE="${NODE:-engine}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete pod engine-k3s-mem-reserve -n kube-system --ignore-not-found --wait=true 2>/dev/null || true

kubectl create configmap engine-k3s-mem-reserve-script -n kube-system \
  --from-file=k3s-write-kubelet-memory-reserve.sh="${SCRIPT_DIR}/k3s-write-kubelet-memory-reserve.sh" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: engine-k3s-mem-reserve
  namespace: kube-system
spec:
  nodeSelector:
    kubernetes.io/hostname: ${NODE}
  hostPID: true
  hostNetwork: true
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: apply
    image: alpine:3.20
    securityContext:
      privileged: true
    env:
    - name: SYSTEM_RESERVED_MEMORY
      value: "${SYSTEM_RESERVED_MEMORY}"
    - name: KUBE_RESERVED_MEMORY
      value: "${KUBE_RESERVED_MEMORY}"
    - name: EVICTION_MEMORY
      value: "${EVICTION_MEMORY}"
    command:
    - sh
    - -c
    - |
      set -eu
      apk add --no-cache python3 >/dev/null
      tr -d '\r' </script/k3s-write-kubelet-memory-reserve.sh >/host/tmp/k3s-write-kubelet-memory-reserve.sh
      chmod +x /host/tmp/k3s-write-kubelet-memory-reserve.sh
      nsenter -t 1 -m -u -i -n -p -- env \
        RESTART_K3S=1 \
        SYSTEM_RESERVED_MEMORY="\${SYSTEM_RESERVED_MEMORY}" \
        KUBE_RESERVED_MEMORY="\${KUBE_RESERVED_MEMORY}" \
        EVICTION_MEMORY="\${EVICTION_MEMORY}" \
        /tmp/k3s-write-kubelet-memory-reserve.sh
      echo DONE
    volumeMounts:
    - name: script
      mountPath: /script
      readOnly: true
    - name: host
      mountPath: /host
  volumes:
  - name: script
    configMap:
      name: engine-k3s-mem-reserve-script
      defaultMode: 0755
  - name: host
    hostPath:
      path: /
      type: Directory
EOF

echo "waiting for engine-k3s-mem-reserve pod..."
for _ in $(seq 1 60); do
  phase="$(kubectl get pod engine-k3s-mem-reserve -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
  sleep 2
done
kubectl logs -n kube-system engine-k3s-mem-reserve || true
kubectl wait --for=condition=Ready "node/${NODE}" --timeout=180s
echo "=== node memory (Capacity / Allocatable) ==="
kubectl get node "$NODE" -o jsonpath='{range .status.capacity}{.memory}{"\n"}{end}{range .status.allocatable}{.memory}{"\n"}{end}'
echo
kubectl describe node "$NODE" | grep -E '^Capacity:|^Allocatable:|  memory:' | head -6

kubectl delete pod engine-k3s-mem-reserve -n kube-system --ignore-not-found
kubectl delete configmap engine-k3s-mem-reserve-script -n kube-system --ignore-not-found

#!/usr/bin/env bash
# Apply system memory reserve on engine via privileged host-mount pod (no SSH required).
set -euo pipefail

SYSTEM_RESERVED_MEMORY="${SYSTEM_RESERVED_MEMORY:-5Gi}"
NODE="${ENGINE_NODE:-engine}"
NAMESPACE="${NAMESPACE:-kube-system}"
POD="engine-k3s-mem-reserve"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESERVE_SCRIPT="$SCRIPT_DIR/k3s-write-kubelet-memory-reserve.sh"
if [[ ! -f "$RESERVE_SCRIPT" ]]; then
  echo "missing $RESERVE_SCRIPT" >&2
  exit 1
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl delete configmap "${POD}-scripts" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true

kubectl create configmap "${POD}-scripts" -n "$NAMESPACE" \
  --from-file=k3s-write-kubelet-memory-reserve.sh="$RESERVE_SCRIPT"

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${POD}
  namespace: ${NAMESPACE}
spec:
  nodeSelector:
    kubernetes.io/hostname: ${NODE}
  hostPID: true
  hostNetwork: true
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: setup
    image: alpine:3.20
    securityContext:
      privileged: true
    env:
    - name: SYSTEM_RESERVED_MEMORY
      value: "${SYSTEM_RESERVED_MEMORY}"
    - name: HOST_ROOT
      value: "/host"
    command:
    - sh
    - -c
    - |
      set -eu
      apk add --no-cache python3 >/dev/null
      cp /scripts/k3s-write-kubelet-memory-reserve.sh /tmp/reserve.sh
      sh /tmp/reserve.sh
      echo DONE
    volumeMounts:
    - name: host
      mountPath: /host
    - name: scripts
      mountPath: /scripts
      readOnly: true
  volumes:
  - name: host
    hostPath:
      path: /
      type: Directory
  - name: scripts
    configMap:
      name: ${POD}-scripts
YAML

echo "waiting for reserve pod..."
for _ in $(seq 1 60); do
  phase="$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
    break
  fi
  sleep 2
done

kubectl logs "pod/${POD}" -n "$NAMESPACE" || true
kubectl get pod "$POD" -n "$NAMESPACE" -o wide || true

echo "engine capacity/allocatable memory:"
kubectl get node "$NODE" -o custom-columns=NAME:.metadata.name,CAP:.status.capacity.memory,ALLOC:.status.allocatable.memory

echo "gitlab:"
kubectl get pod -n gitlab gitlab-0 -o wide || true

#!/usr/bin/env python3
"""Generate split master/worker DDP jobs and update smoke script."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRAINING = ROOT / "k8s/training"

# Keep shared resources in pytorch-ddp-smoke.yaml (truncate job section)
shared = (TRAINING / "pytorch-ddp-smoke.yaml").read_text(encoding="utf-8")
if "kind: Job" in shared:
    shared = shared.split("---\napiVersion: batch/v1\nkind: Job")[0].rstrip() + "\n"

master_job = """---
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-ddp-master
  namespace: training
  labels:
    app: pytorch-ddp-smoke
    ddp-role: master
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: pytorch-ddp-smoke
        ddp-role: master
        job-name: pytorch-ddp-smoke
        batch.kubernetes.io/job-completion-index: "0"
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      restartPolicy: Never
      runtimeClassName: nvidia
      nodeSelector:
        gpu: nvidia
        kubernetes.io/hostname: engine
      containers:
        - name: trainer
          image: pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime
          command: ["/bin/bash", "/scripts/entrypoint.sh"]
          env:
            - name: JOB_COMPLETION_INDEX
              value: "0"
            - name: ENGINE_MASTER_IP
              value: "192.168.10.32"
            - name: HOST_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: NCCL_DEBUG
              value: INFO
            - name: NCCL_IB_DISABLE
              value: "1"
            - name: NCCL_P2P_DISABLE
              value: "1"
            - name: NCCL_SOCKET_IFNAME
              value: eno1,eth0
          ports:
            - containerPort: 29500
              name: dist
          resources:
            limits:
              nvidia.com/gpu: 1
              memory: 4Gi
            requests:
              cpu: "2"
              memory: 2Gi
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: pytorch-ddp-smoke
            defaultMode: 0755
"""

worker_job = """---
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-ddp-worker
  namespace: training
  labels:
    app: pytorch-ddp-smoke
    ddp-role: worker
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: pytorch-ddp-smoke
        ddp-role: worker
        job-name: pytorch-ddp-smoke
        batch.kubernetes.io/job-completion-index: "1"
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      restartPolicy: Never
      runtimeClassName: nvidia
      nodeSelector:
        gpu: nvidia
      tolerations:
        - key: workload
          operator: Equal
          value: burst
          effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: [desktop]
                  - key: burst
                    operator: In
                    values: ["enabled"]
      initContainers:
        - name: wait-master
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              echo "waiting for master ${ENGINE_MASTER_IP}:${MASTER_PORT}"
              until nc -z "${ENGINE_MASTER_IP}" "${MASTER_PORT}"; do sleep 2; done
          env:
            - name: ENGINE_MASTER_IP
              value: "192.168.10.32"
            - name: MASTER_PORT
              value: "29500"
      containers:
        - name: trainer
          image: pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime
          command: ["/bin/bash", "/scripts/entrypoint.sh"]
          env:
            - name: JOB_COMPLETION_INDEX
              value: "1"
            - name: ENGINE_MASTER_IP
              value: "192.168.10.32"
            - name: HOST_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: NCCL_DEBUG
              value: INFO
            - name: NCCL_IB_DISABLE
              value: "1"
            - name: NCCL_P2P_DISABLE
              value: "1"
            - name: NCCL_SOCKET_IFNAME
              value: eno1,eth0
          resources:
            limits:
              nvidia.com/gpu: 1
              memory: 4Gi
            requests:
              cpu: "2"
              memory: 2Gi
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: pytorch-ddp-smoke
            defaultMode: 0755
"""

(TRAINING / "pytorch-ddp-smoke.yaml").write_text(shared + "\n", encoding="utf-8", newline="\n")
(TRAINING / "pytorch-ddp-master-job.yaml").write_text(master_job.lstrip(), encoding="utf-8", newline="\n")
(TRAINING / "pytorch-ddp-worker-job.yaml").write_text(worker_job.lstrip(), encoding="utf-8", newline="\n")
print("wrote split DDP manifests")

smoke = ROOT / "scripts/k8s-training-smoke.sh"
text = smoke.read_text(encoding="utf-8")
old_ddp = """run_ddp() {
  if ! kubectl get node desktop -o jsonpath='{.metadata.labels.burst}' 2>/dev/null | grep -qx enabled; then
    echo "==> DDP needs desktop burst mode: run ./scripts/desktop-gpu-burst-on.sh first" >&2
    exit 1
  fi
  echo "==> PyTorch DDP smoke (engine + desktop, burst enabled)"
  kubectl delete job pytorch-ddp-smoke -n training --ignore-not-found
  kubectl apply -f "$ROOT/k8s/training/pytorch-ddp-smoke.yaml"
  wait_job training pytorch-ddp-smoke 600
}"""
new_ddp = """run_ddp() {
  if ! kubectl get node desktop -o jsonpath='{.metadata.labels.burst}' 2>/dev/null | grep -qx enabled; then
    echo "==> DDP needs desktop burst mode: run ./scripts/desktop-gpu-burst-on.sh first" >&2
    exit 1
  fi
  echo "==> PyTorch DDP smoke (engine master + desktop worker, burst enabled)"
  echo "==> ensure engine UFW allows DDP: ./scripts/homelab-engine-ddp-ufw.sh (on engine)"
  kubectl apply -f "$ROOT/k8s/training/pytorch-ddp-smoke.yaml"
  kubectl delete job pytorch-ddp-master pytorch-ddp-worker -n training --ignore-not-found
  kubectl apply -f "$ROOT/k8s/training/pytorch-ddp-master-job.yaml"
  wait_job training pytorch-ddp-master 300
  kubectl apply -f "$ROOT/k8s/training/pytorch-ddp-worker-job.yaml"
  wait_job training pytorch-ddp-worker 600
}"""
if old_ddp not in text:
    raise SystemExit("run_ddp block not found in smoke script")
smoke.write_text(text.replace(old_ddp, new_ddp, 1), encoding="utf-8", newline="\n")
print("updated k8s-training-smoke.sh")

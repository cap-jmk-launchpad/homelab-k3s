#!/usr/bin/env bash
set -euo pipefail
POD=$(kubectl -n training get pod -l job-name=pytorch-ddp-smoke,batch.kubernetes.io/job-completion-index=1 \
  -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -1)
echo "pod=$POD"
kubectl -n training exec "$POD" -- python3 -c "
import socket
for name in ['pytorch-ddp-master', 'pytorch-ddp-master.training.svc.cluster.local', 'kubernetes.default']:
    try:
        print(name, '->', socket.gethostbyname(name))
    except Exception as e:
        print(name, '-> FAIL', e)
for addr in ['10.42.1.79', '10.43.121.45']:
    try:
        s = socket.create_connection((addr, 29500), timeout=3)
        print('tcp', addr, 'ok')
        s.close()
    except Exception as e:
        print('tcp', addr, e)
"

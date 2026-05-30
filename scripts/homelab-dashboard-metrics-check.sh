#!/usr/bin/env bash
set -euo pipefail
PROM_URL="${PROM_URL:-http://10.42.1.22:9090}"
query() {
  curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(r[0]["value"][1] if r else "NO DATA")'
}
echo "Memory Utilisation (dashboard expr, empty cluster):"
query '1 - sum(:node_memory_MemAvailable_bytes:sum{cluster=""}) / sum(node_memory_MemTotal_bytes{job="node-exporter",cluster=""})'
echo "Memory Requests Commitment:"
query 'sum(namespace_memory:kube_pod_container_resource_requests:sum{cluster=""}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="memory",cluster=""})'
echo "Memory Limits Commitment:"
query 'sum(namespace_memory:kube_pod_container_resource_limits:sum{cluster=""}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="memory",cluster=""})'
echo "CPU Utilisation:"
query 'cluster:node_cpu:ratio_rate5m{cluster=""}'
echo "allocatable memory sum:"
query 'sum(kube_node_status_allocatable{job="kube-state-metrics",resource="memory"})'
echo "memory requests sum:"
query 'sum(namespace_memory:kube_pod_container_resource_requests:sum)'

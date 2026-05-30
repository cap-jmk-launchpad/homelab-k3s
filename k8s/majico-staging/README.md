# majico-staging

## Network policies

Apply after staging workloads are running:

```bash
kubectl apply -f k8s/majico-staging/network-policies.yaml
```

Policies:

- **default-deny-ingress** — deny all ingress unless another policy allows it
- **allow-intra-namespace** — pod-to-pod traffic within `majico-staging`
- **allow-lan-nodeport-app** / **allow-lan-nodeport-kong** — LAN (`192.168.10.0/24`) to NodePort backends on ports 3000 and 8000

NodePorts `30080` and `30000` on blackpearl are unchanged; UFW on the control plane restricts them to the LAN.

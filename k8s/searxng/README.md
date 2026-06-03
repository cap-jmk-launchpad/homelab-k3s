# SearXNG on homelab k3s (`search.klaut.pro`)

Privacy-focused metasearch for humans and AI agents. Exposed via **li-httpd** edge routing (not in-cluster Ingress — Traefik is disabled on this cluster).

| Component | Value |
|-----------|-------|
| Namespace | `searxng` |
| NodePort | **30479** (blackpearl loopback backend) |
| Public URL | `https://search.klaut.pro` |
| JSON API | `GET /search?q=...&format=json` |

## Architecture

```
Internet / LAN
      │
      ▼
blackpearl :443 (li-httpd TLS, Let's Encrypt)
      │  Host: search.klaut.pro
      ▼
127.0.0.1:30479  ←  k3s NodePort → searxng pod (8080)
                              └── valkey sidecar (limiter)
```

## Deploy

### 1. DNS (public)

Point **`search.klaut.pro`** at your public edge IP (the host that terminates HTTPS — typically blackpearl behind Fritz!Box port-forward).

| Record | Name | Value | TTL |
|--------|------|-------|-----|
| **A** (preferred) | `search` | `<your-public-IPv4>` | 300–3600 |
| **AAAA** (optional) | `search` | `<your-public-IPv6>` | 300–3600 |

Use **A** when you have a stable IPv4. Use **CNAME** only if you front with a CDN or another hostname (e.g. `search` → `edge.example.com`); do not CNAME to a NodePort.

**Router:** forward **TCP 443** (and **80** for ACME HTTP-01) to blackpearl, same as other public homelab sites.

Verify:

```bash
dig +short search.klaut.pro A
curl -sI https://search.klaut.pro/health
```

### 2. Secret (once)

```bash
bash scripts/k8s-searxng-secret.sh
```

Or copy [secret.example.yaml](./secret.example.yaml) to `secret.yaml` (gitignored) and `kubectl apply -f k8s/searxng/secret.yaml`.

### 3. Apply workload

From a machine with kubeconfig:

```bash
bash scripts/k8s-searxng-apply.sh
```

Or:

```bash
kubectl apply -k k8s/searxng/
kubectl -n searxng rollout status deployment/searxng
```

### 4. Edge route + TLS

Sync edge config to blackpearl and reload li-httpd:

```bash
rsync -avz k8s/edge/ scripts/edge-lis-*.sh s4il0r@blackpearl:~/staging/beelink-cleanup/
ssh s4il0r@blackpearl 'cd ~/staging/beelink-cleanup && bash scripts/edge-lis-validate.sh && sudo bash scripts/edge-lis-apply.sh'
```

`search.klaut.pro` is included in default ACME domains in [gen-https-overlay.py](../edge/gen-https-overlay.py). Override if needed:

```bash
export HOMELAB_ACME_DOMAINS="search.klaut.pro,..."
export HOMELAB_ACME_EMAIL="you@klaut.pro"
sudo -E bash scripts/edge-lis-apply.sh
```

### 5. Smoke test

```bash
curl -sf -H 'Host: search.klaut.pro' http://127.0.0.1/health
curl -sf 'https://search.klaut.pro/search?q=searxng&format=json' | head
```

## Agent / API usage

SearXNG returns HTML by default; JSON is enabled in [config/settings.yml](./config/settings.yml).

```bash
curl -G 'https://search.klaut.pro/search' \
  --data-urlencode 'q=kubernetes nodeport' \
  --data-urlencode 'format=json'
```

**LiteLLM / Frona / custom agents:** set `SEARXNG_API_BASE=https://search.klaut.pro` (or pass `api_base` per call).

Response shape: SearXNG native JSON (`results[]` with `title`, `url`, `content`, etc.). Wrap or map to OpenAI-style `search` objects if your client expects that schema.

## Rate limiting & auth

| Layer | What it does |
|-------|----------------|
| SearXNG limiter + Valkey | Bot detection, per-IP sliding windows; `link_token = false` for JSON agents |
| li-httpd edge | Host routing + TLS; add API keys at edge for paid tiers |

**Paid tiers:** SearXNG alone is not a billing product. Add a thin **API gateway** in front (recommended path):

1. **Auth proxy** (Caddy, nginx, or small Go/Node service) on a separate NodePort or path prefix `/v1/search`
2. Validate `Authorization: Bearer <api_key>` or `X-Api-Key`
3. Map keys → rate limits (Redis) and usage counters for billing
4. Proxy allowed requests to `http://127.0.0.1:30479/search?...`
5. Optionally add `pass_ip` in `limiter.toml` for the gateway’s loopback IP so end-user IPs flow via `X-Forwarded-For`

## Monetization & pricing

See [docs/search-klaut-pro.md](../../docs/search-klaut-pro.md#monetization-practical) for competitive pricing, tier suggestions, and billing hooks.

## Monitoring

| Signal | Source |
|--------|--------|
| Pod health | `kubectl -n searxng get pods` |
| Ready | `GET /healthz` |
| Metrics | `GET /metrics` (Prometheus annotations on deployment; scrape via kube-prometheus or SigNoz) |
| Logs | `kubectl -n searxng logs deploy/searxng -f` |
| Dashboards | Add QPS/latency panels to Grafana (`30300`) |

## Operations

```bash
kubectl -n searxng logs deploy/searxng -c searxng -f
kubectl -n searxng get pods,svc
```

Pin the image tag in [deployment.yaml](./deployment.yaml) when upgrading; test JSON output after each bump.

## Related

- [k8s/edge/README.md](../edge/README.md) — li-httpd ingress pattern
- [docs/edge-ingress.md](../../docs/edge-ingress.md)

# search.klaut.pro — SearXNG for agents

Self-hosted [SearXNG](https://github.com/searxng/searxng) metasearch on the homelab k3s cluster, fronted by **li-httpd** (not Kubernetes Ingress / cert-manager).

## Architecture

```
Internet / LAN
      │
      ▼
search.klaut.pro  →  blackpearl li-httpd (:80 / :443)
      │
      ▼
127.0.0.1:30479  (k8s NodePort → searxng pod)
```

Manifests: [k8s/searxng/](../k8s/searxng/). Edge route: [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml).

## DNS (manual)

| Step | Action |
|------|--------|
| 1 | At your DNS provider for **klaut.pro**, add an **A** (or **AAAA**) record: `search` → your public WAN IP (same as other `*.klaut.pro` services if you already expose the homelab). |
| 2 | On **Fritz!Box** (or router): forward **TCP 80** and **TCP 443** to blackpearl (`192.168.10.41` in this repo’s examples). HTTP-01 for Let’s Encrypt needs **:80**. |
| 3 | Optional LAN override: `/etc/hosts` or Fritz local DNS `search.klaut.pro` → `192.168.10.41` for testing before public DNS propagates. |

Confirm:

```bash
dig +short search.klaut.pro
curl -sS -o /dev/null -w '%{http_code}\n' https://search.klaut.pro/healthz
```

## TLS

Homelab TLS is terminated on **li-httpd** (`:443`), not cert-manager.

When applying edge config on blackpearl, include the hostname in ACME domains:

```bash
export HOMELAB_ACME_EMAIL="you@example.com"
export HOMELAB_ACME_DOMAINS="search.klaut.pro,majico.d3bu7.com,api.majico.d3bu7.com"
sudo bash scripts/edge-lis-apply.sh
```

Or install certs under `/etc/letsencrypt/live/...` and use `[server.tls.manual]` per [edge-ingress.md](edge-ingress.md).

## Deploy checklist

```bash
bash scripts/k8s-searxng-secret.sh
bash scripts/k8s-searxng-apply.sh
# rsync k8s/edge + scripts to blackpearl, then:
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh
```

## Agent / app API

SearXNG has no native API keys. Authentication and billing belong in a **gateway** in front (see monetization below). The search API is the standard HTTP JSON endpoint.

### Required parameters

| Param | Value | Notes |
|-------|--------|------|
| `q` | search string | URL-encoded |
| `format` | `json` | Must be enabled in settings (already in ConfigMap) |

### Optional parameters

| Param | Examples |
|-------|----------|
| `categories` | `general`, `it`, `science`, `news` |
| `engines` | `duckduckgo`, `google` (instance-dependent) |
| `language` | `en`, `de` |
| `pageno` | `1`, `2`, … |
| `time_range` | `day`, `week`, `month`, `year` |

### Example: curl

```bash
curl -sS 'https://search.klaut.pro/search' \
  --get \
  --data-urlencode 'q=kubernetes nodeport ingress' \
  --data-urlencode 'format=json' \
  --data-urlencode 'categories=it' \
  -H 'Accept: application/json' \
  -H 'User-Agent: MyAgent/1.0 (contact@example.com)'
```

### Example: Python (stdlib)

```python
import json
import urllib.parse
import urllib.request

BASE = "https://search.klaut.pro"
# Optional gateway key (you implement): headers["X-Api-Key"] = "YOUR_API_KEY"

def search(query: str, *, categories: str = "general") -> dict:
    params = urllib.parse.urlencode({
        "q": query,
        "format": "json",
        "categories": categories,
    })
    req = urllib.request.Request(
        f"{BASE}/search?{params}",
        headers={
            "Accept": "application/json",
            "User-Agent": "KlautAgent/1.0",
            # "X-Api-Key": os.environ["SEARCH_API_KEY"],
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

data = search("SearXNG json api rate limit")
for hit in data.get("results", [])[:5]:
    print(hit["title"], hit["url"])
```

### Response shape (abbreviated)

```json
{
  "query": "kubernetes nodeport",
  "number_of_results": 0,
  "results": [
    {
      "title": "...",
      "url": "https://...",
      "content": "snippet...",
      "engine": "duckduckgo",
      "score": 1.0,
      "category": "it"
    }
  ],
  "suggestions": [],
  "answers": [],
  "corrections": [],
  "unresponsive_engines": []
}
```

### LiteLLM / Open WebUI

```bash
export SEARXNG_API_BASE="https://search.klaut.pro"
```

```python
# LiteLLM search helper (if installed)
from litellm import search
resp = search(query="latest k3s release notes", search_provider="searxng")
```

### Rate limiting

- SearXNG **limiter** is enabled (`limiter.toml`); homelab LAN `192.168.10.0/24` is on `pass_ip` for debugging.
- Public clients share instance rate limits. For paid tiers, enforce quotas at your **API gateway** (per API key), not only inside SearXNG.

### Hardening for production

1. Put **Kong**, **Traefik**, or **li-httpd auth** in front with `X-Api-Key` validation.
2. Restrict `formats` to `json` only if you drop the HTML UI.
3. Set `server.image_proxy: false` (default here) unless you need thumbnails.
4. Monitor `unresponsive_engines` in responses; disable broken engines in settings.

---

## Monetization (practical)

SearXNG is free software; **your product** is reliable search API access for agents. Comparable paid search APIs (2025–2026 ballpark):

| Provider | Typical retail | Notes |
|----------|----------------|-------|
| SerpAPI | ~$75/mo for 5k searches | Google-heavy, familiar JSON |
| Tavily | ~$0.01/search pay-as-you-go | Agent-oriented |
| Brave Search API | ~$5 per 1k queries | Simple HTTP API |
| Exa | usage-based | Neural / semantic |

Self-hosted SearXNG cost is mostly **egress + your time + one small VM**. Price below retail API while staying sustainable.

### Suggested tiers

| Tier | Price | Quota | Audience |
|------|-------|-------|----------|
| **Free** | $0 | 50 searches/day/IP or 200/day/key | Hobby agents, try-before-buy |
| **Builder** | $9/mo | 5,000 searches/mo | Indie devs, single agent |
| **Team** | $29/mo | 30,000 searches/mo | Small product teams |
| **Agent infra** | $99/mo | 150,000 searches/mo + SLA email | B2B, multiple agents |
| **Enterprise** | custom | dedicated instance, allowlist engines | Contract, invoice |

Overage: **$2 per 1,000** queries (undercuts ~$5/1k Brave-style pricing).

### How to implement billing (minimal stack)

1. **API keys** — issue `klaut_sk_live_...` in your app DB; never store in git.
2. **Gateway** — Kong plugin or small Go/Node proxy on `api.search.klaut.pro` that:
   - validates `X-Api-Key`
   - increments Redis counter per key/month
   - returns `429` with `Retry-After` when over quota
   - proxies to `https://search.klaut.pro/search?...`
3. **Metering** — export daily counts to Stripe Usage Records or Polar.sh meters.
4. **Payments** — Stripe Checkout for self-serve; manual invoice for B2B.
5. **Freemium hook** — Cursor skill / SDK docs point to `api.search.klaut.pro` with free tier key; upgrade link in `429` JSON body.

### Positioning

- **Privacy**: no per-user tracking like ad search; good for EU-minded customers.
- **Agent-native**: JSON + metasearch (many engines) vs single-engine APIs.
- **Cost**: you control engine mix; drop expensive engines on free tier.

### What not to do

- Do not resell Google results in violation of engine ToS — use SearXNG’s configured engines and respect their policies.
- Do not expose an unauthenticated public instance at scale; you will absorb abuse and engine blocks.

---

## Related

- [docs/agentic-platform.md](agentic-platform.md) — unified search + Vault BYOK product
- [k8s/searxng/README.md](../k8s/searxng/README.md)
- [k8s/edge/README.md](../k8s/edge/README.md)
- [edge-ingress.md](edge-ingress.md)

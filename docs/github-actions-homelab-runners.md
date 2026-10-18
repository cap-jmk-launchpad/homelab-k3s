# Homelab GitHub Actions runners (Majico, Librebase, Obsevia)

GitHub-hosted runners cannot reach Fritz-LAN staging (`majico.d3bu7.com`, `stage.librebase.xyz`, Obsevia demo namespaces on k3s). **ARC runner scale sets** on homelab k3s provide org-level listeners with product-specific labels.

## For humans

1. Install secrets: `LAUNCHPAD_ENV=../.env ./scripts/k8s-github-actions-secret.sh`
2. Apply: `./scripts/k8s-github-actions-apply.sh`
3. In each GitHub org, confirm runners under **Settings → Actions → Runners** (group `homelab-k8s`).
4. Enable repo/org variables documented per product (e.g. `MAJICO_SELF_HOSTED_RUNNER=true`).

Manifests: [k8s/github-actions/](../k8s/github-actions/).

## For Cursor Cloud Agents

When you change CI/CD or need kubectl/Playwright against homelab:

| Product | Repo examples | Use `runs-on` | Repo variable |
| --- | --- | --- | --- |
| **Majico** | `majico-xyz/majico.xyz` | `[self-hosted, majico-staging, linux]` | `MAJICO_SELF_HOSTED_RUNNER=true` |
| **Librebase** | `librebase-official/librebase`, `librebase-saas` | `[self-hosted, librebase-homelab, linux]` | `LIBREBASE_SELF_HOSTED_RUNNER=true` (when wired) |
| **Obsevia** | `obsevia-compliance/obsevia-kubernetes` | `[self-hosted, obsevia-homelab, linux]` | `HOMELAB_K8S_HEALTH_ENABLED=true` |

**Do not** assume homelab reachability on `ubuntu-latest`. Prefer Shiphook deploy jobs on GitHub-hosted runners when only the cluster needs updating (see Majico `staging-gate.yml`).

**Infra changes** (new label, scale limits, tokens): edit `homelab-k3s` (`cap-jmk-launchpad/homelab-k3s`), not app repos.

### Agent notification

- **GitHub:** [homelab-k3s#9](https://github.com/cap-jmk-launchpad/homelab-k3s/issues/9) — subscribe for runner deploy/outage updates; link from product issues when CI behavior changes.
- **Direct message:** ping the operator on Slack when runners are down and cloud agents queue homelab jobs (optional automation via Cursor subscriptions on that issue).

### Quick checks (from a machine with kubeconfig)

```bash
kubectl get autoscalingrunnersets -n github-actions
kubectl get pods -n github-actions -l actions.github.com/scale-set-name=majico-homelab
```

From a registered runner pod (or future debug job):

```bash
curl -fsSL --max-time 15 https://majico.d3bu7.com/
curl -fsSL --max-time 15 https://stage.librebase.xyz/
```

## Tokens

Store in Vault or `launchpad/.env` (never commit):

| Env var | Secret name in k8s |
| --- | --- |
| `GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO` | `majico-xyz-arc` |
| `GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE` | `librebase-official-arc` |
| `GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA` | `obsevia-compliance-arc` |

Org admin PAT or GitHub App installation token with permission to register org runners.

## Related product docs

- Majico: `majico.xyz/docs/internal/staging-e2e-runners.md`
- Obsevia: `obsevia-kubernetes/.github/workflows/k8s-staging-health.yml`

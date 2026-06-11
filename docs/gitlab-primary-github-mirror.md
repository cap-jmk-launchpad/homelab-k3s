# GitLab-primary, GitHub-mirror (li-langverse)

Develop on **GitLab** (`gitlab.lilangverse.xyz/li-langverse/*`). **GitHub** is a read-only mirror. Container images stay on **GHCR** (`ghcr.io/li-langverse/*`).

## Remotes (after cutover)

| Remote | URL | Push |
|--------|-----|------|
| `origin` | `https://gitlab.lilangverse.xyz/li-langverse/<repo>.git` | yes |
| `github` | `https://github.com/li-langverse/<repo>.git` | **disabled** (fetch only) |

Apply locally:

```powershell
cd li-cursor-agents
.\scripts\configure-gitlab-remotes.ps1
```

## Tokens

| Variable | Use |
|----------|-----|
| `GITLAB_TOKEN` | Git clone/push, GitLab API, K8s `li-agents-secrets` |
| `GH_TOKEN` | GitHub API, GHCR pull, Pages workflows |
| `GH_MIRROR_TOKEN` | GitLab→GitHub push mirror (blackpearl only) |

Store locally in `li/.env.gitlab` (copy from `.env.gitlab.example`). Never commit secrets.

### Create PAT

1. Open [Personal access tokens](https://gitlab.lilangverse.xyz/-/user_settings/personal_access_tokens)
2. Scopes: **read_repository**, **write_repository** (add **api** for MR/issue automation)
3. Set `GITLAB_TOKEN=<token>` in `li/.env.gitlab` or `li/.env.local`

### Windows credential helper (no GCM popups)

```powershell
cd homelab-k3s
npm run windows:git-auth
```

Homelab GitLab uses a private CA — `windows-git-auth-setup.ps1` stores `oauth2:<PAT>` in Credential Manager. Optional: `git config --global http.https://gitlab.lilangverse.xyz/.sslVerify false`.

## K8s goal-directed workers

When `GITLAB_TOKEN` is loaded:

```powershell
cd li-cursor-agents
.\scripts\rollout-gitlab-remotes-k8s.ps1
```

Uses `~/.kube/config-homelab`, patches `li-agents-secrets`, restarts goal-directed deployments.

## Mirror drift recovery

If GitHub `main` advanced without GitLab (e.g. mistaken GitHub admin-merge):

```powershell
cd <repo>
git fetch origin github
git checkout main
git merge github/main    # or cherry-pick; resolve conflicts favoring GitLab policy
git push origin main     # GitLab push-mirror updates GitHub
```

Never leave GitHub ahead of GitLab for li-langverse code repos.

If GitLab already has the correct merge (e.g. MR merged on GitLab) but GitHub was updated by mistake, **do not** cherry-pick onto GitHub. GitLab stays canonical; run the mirror so GitHub catches up:

```powershell
cd li-cursor-agents
.\scripts\run-gitlab-github-mirror-local.ps1   # or wait for li-swarm CronJob
.\scripts\assert-gitlab-primary.ps1
```

## Drift check (CI / manual)

```powershell
cd li-cursor-agents
.\scripts\assert-gitlab-primary.ps1
```

Fails when `github/main` is not an ancestor of `origin/main` (GitHub ahead of GitLab).

## Excluded repos

| Repo | Policy |
|------|--------|
| `homelab-k3s` | `cap-jmk-launchpad` — GitHub-primary |
| `klaut-*` | Foreign product track |

See also: `li/.cursor/rules/gitlab-primary-github-mirror.mdc`, `homelab-k3s/docs/windows-git-auth.md`.

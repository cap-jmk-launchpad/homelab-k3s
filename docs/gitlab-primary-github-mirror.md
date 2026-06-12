# GitLab-primary; GitHub = GHCR only (li-langverse)

Develop on **GitLab** (`gitlab.lilangverse.xyz/li-langverse/*`). **GitHub** (`github.com/li-langverse`) is **not** a git backup mirror for day-to-day work — the org uses GitHub **only for GHCR** (`ghcr.io/li-langverse/*`) and legacy Pages workflows that still deploy from mirrored refs until fully migrated.

## Remotes (product repos)

| Remote | URL | Push |
|--------|-----|------|
| `origin` | `https://gitlab.lilangverse.xyz/li-langverse/<repo>.git` | **yes** |
| `github` | — | **do not use** for git (GHCR login only) |

Apply locally:

```powershell
cd li-cursor-agents
.\scripts\configure-gitlab-remotes.ps1
```

## Tokens

| Variable | Use |
|----------|-----|
| `GITLAB_TOKEN` | Git clone/push, GitLab API, K8s `li-agents-secrets` |
| `GH_TOKEN` | **GHCR** push/pull, GitHub API where still required |
| `GH_MIRROR_TOKEN` | **Deprecated** — git push mirrors to GitHub are being retired |

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

## If old GitHub git mirrors still exist

Legacy `github.com/li-langverse/*` repos may lag or be archived. **GitLab is canonical.** Do not merge on GitHub. If you need to retire a mirror, archive the GitHub repo and update docs — do not treat GitHub as backup git.

## Drift check (CI / manual)

```powershell
cd li-cursor-agents
.\scripts\assert-gitlab-primary.ps1
```

Only relevant while GitHub mirrors still exist; fails when `github/main` is not an ancestor of `origin/main`.

## Excluded repos

| Repo | Policy |
|------|--------|
| `homelab-k3s` | `cap-jmk-launchpad` — GitHub-primary (infra) |
| `klaut-*` | Foreign product track |

See also: `li/.cursor/rules/gitlab-primary-github-mirror.mdc`, `homelab-k3s/docs/windows-git-auth.md`.

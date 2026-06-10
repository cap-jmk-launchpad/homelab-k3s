# Windows git auth (stop Credential Manager popups)

Cursor agents, mirror scripts, and manual `git push`/`fetch` against **GitLab** were opening repeated **Git Credential Manager** sign-in dialogs because:

1. **GitLab** (`gitlab.lilangverse.xyz`) had no stored credentials — only the system `credential.helper=manager`, which prompts interactively.
2. **Stuck background git processes** from prior agent runs (`git push gitlab …`, `git ls-remote`, `git push origin` to GitLab) kept GCM dialogs alive for hours.
3. **GitHub** was already fine via `gh auth git-credential`.

NodePort remotes (`http://192.168.10.32:30481`, etc.) in `lic` also need generic credentials when used from Windows.

## One-time setup

### 1. Mint / refresh PAT

From repo root (needs homelab `KUBECONFIG`):

```powershell
cd homelab-k3s
$env:OUT_FILE = "..\.env.local"
npm run gitlab:auth
```

`.env.local` is gitignored; never commit tokens.

### 2. Store credentials (no popups)

```powershell
cd homelab-k3s
npm run windows:git-auth
```

This writes `oauth2:<GITLAB_TOKEN>` into **Windows Credential Manager** for:

| Host | Use |
|------|-----|
| `https://gitlab.lilangverse.xyz` | Primary clone/push |
| `http://192.168.10.32:30481` | `lic` remote `nodeport-push` |
| `http://192.168.10.33:30481` | LAN NodePort bypass |
| `http://127.0.0.1:18080` / `:30481` | Local tunnel scripts |

Git config set:

```ini
credential.helper=manager
credential.https://gitlab.lilangverse.xyz.provider=generic
credential.https://gitlab.lilangverse.xyz.helper=manager
```

**GitHub** keeps `gh auth git-credential` (check with `gh auth status`).

### 3. Verify

```powershell
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "never"
git -C ..\lic ls-remote gitlab HEAD
git -C ..\lic ls-remote origin HEAD
```

Both should return a commit hash with no dialog.

## If popups return

### Kill stuck git processes

Hung agent pushes leave `git-credential-manager get` waiting on UI:

```powershell
Get-CimInstance Win32_Process -Filter "Name='git.exe' OR Name='git-credential-manager.exe'" |
  Where-Object { $_.CommandLine -match 'gitlab\.lilangverse|credential-manager' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### Refresh token

PAT expired or revoked:

```powershell
cd homelab-k3s
$env:OUT_FILE = "..\.env.local"
npm run gitlab:auth
npm run windows:git-auth
```

### GitHub re-login

```powershell
# Non-interactive if GH_MIRROR_TOKEN or GH_TOKEN is in .env.local:
$tok = (Get-Content ..\.env.local | Where-Object { $_ -match '^GH_MIRROR_TOKEN=' }) -replace '^GH_MIRROR_TOKEN=',''
$tok | gh auth login --with-token
```

## Remotes in this workspace

| Repo | GitLab remote | GitHub remote |
|------|---------------|---------------|
| `lic` | `gitlab` → HTTPS edge; `nodeport-push` → HTTP LAN | `origin` |
| `gitlab-github-mirror` | `origin` | `github` |
| `li-cursor-agents`, `lib` | `gitlab` / `origin` | `origin` / `github` |
| `homelab-k3s` | — | `origin` (cap-jmk-launchpad) |

Bare remotes stay token-free; scripts that push via NodePort should use `GITLAB_TOKEN` in the URL only at runtime (see `homelab-k3s/scripts/git-push.sh`), not in `.git/config`.

## Related

- [gitlab-fast-iteration.md](gitlab-fast-iteration.md) — mint PAT, NodePort bypass from blackpearl
- Org policy: develop on GitLab, GitHub is read-only mirror

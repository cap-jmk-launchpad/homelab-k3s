# Ollama on engine (homelab GPU)

**engine** (`192.168.10.32`) runs [Ollama](https://ollama.com/) on the host NVIDIA GPU (RTX 3060). Workloads in k3s (Majico staging, etc.) call it over LAN — no in-cluster Ollama pod required.

| API | URL |
|-----|-----|
| Native | `http://192.168.10.32:11434/api/tags` |
| OpenAI-compatible | `http://192.168.10.32:11434/v1/chat/completions` |

Default model: `qwen3.5:9b` (`OLLAMA_MODEL` override).

## Deploy from your PC

Homelab key: [`homelab`](homelab-ssh-keys.md) (gitignored private key next to this repo).

```bash
cd beelink-cleanup
bash scripts/engine-ollama-deploy.sh
```

PowerShell (Git Bash):

```powershell
bash C:\Users\Julian\Documents\Programming\beelink-cleanup\scripts\engine-ollama-deploy.sh
```

## Install on engine only

```bash
ssh -i homelab s4il0r@192.168.10.32
cd ~/beelink-cleanup && git pull
bash scripts/engine-ollama-install.sh
```

## Majico / app env

```yaml
OPENAI_BASE_URL: http://192.168.10.32:11434/v1
OPENAI_MODEL: qwen3.5:9b
OPENAI_API_KEY: ollama
```

See also [engine-k3s-worker.md](engine-k3s-worker.md), [k8s/gpu/README.md](../k8s/gpu/README.md).

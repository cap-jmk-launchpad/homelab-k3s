#!/usr/bin/env bash
# Install Ollama on engine (NVIDIA GPU) and expose HTTP API on the LAN.
# Run ON engine: bash scripts/engine-ollama-install.sh
set -euo pipefail

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3.5:9b}"
OLLAMA_LISTEN="${OLLAMA_LISTEN:-0.0.0.0:11434}"
LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

echo "[engine-ollama] GPU check..."
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. Install NVIDIA drivers on engine first." >&2
  exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

echo "[engine-ollama] Installing Ollama (if missing)..."
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

echo "[engine-ollama] Configuring systemd (listen on ${OLLAMA_LISTEN})..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_LISTEN}"
Environment="OLLAMA_NUM_GPU=1"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

echo "[engine-ollama] Waiting for API..."
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "[engine-ollama] Pulling ${OLLAMA_MODEL} (GPU)..."
ollama pull "${OLLAMA_MODEL}"

echo "[engine-ollama] Firewall (ufw optional)..."
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow from "${LAN_CIDR}" to any port 11434 proto tcp comment 'Ollama engine API' || true
fi

ENGINE_IP="$(hostname -I | awk '{print $1}')"
echo "[engine-ollama] Health:"
curl -sf "http://127.0.0.1:11434/api/tags" | head -c 500
echo
echo "[engine-ollama] Done."
echo "[engine-ollama] Native:  http://${ENGINE_IP}:11434/api/tags"
echo "[engine-ollama] OpenAI:  http://${ENGINE_IP}:11434/v1/chat/completions"

#!/usr/bin/env bash
# Local LLM Coding Server setup for Apple Silicon (M1/M2/M3) - 32GB RAM
# Run on the headless M1 MacBook Pro.
# Usage:  bash setup-llm-server.sh
# Env toggles:
#   INSTALL_WEBUI=1    (default 0) install Open WebUI in Docker
#   INSTALL_TAILSCALE=1
#   PULL_MODELS=1

set -euo pipefail

INSTALL_WEBUI="${INSTALL_WEBUI:-0}"
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-1}"
PULL_MODELS="${PULL_MODELS:-1}"

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }
install_formula_if_missing() {
  local formula="$1"

  if brew list --formula "$formula" >/dev/null 2>&1; then
    log "$formula already installed. Skipping."
  else
    log "Installing $formula..."
    brew install "$formula"
  fi
}
ensure_sudo() {
  log "Requesting sudo access upfront (for smoother run)..."
  sudo -v || die "Sudo authentication failed."
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# ---- Sanity checks ----
[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
[[ "$(uname -m)" == "arm64" ]]  || die "Apple Silicon (arm64) only."
ensure_sudo

# ---- Homebrew ----
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  log "Homebrew already installed."
fi

# ---- Core CLI tools ----
log "Ensuring core tools: ollama, git, wget, htop, jq..."
for formula in ollama git wget htop jq; do
  install_formula_if_missing "$formula"
done

# ---- Tailscale ----
# Same idea as Docker: avoid brew install --cask if the app already lives in /Applications.
if [[ "$INSTALL_TAILSCALE" == "1" ]]; then
  if brew list --cask tailscale >/dev/null 2>&1; then
    log "Tailscale already installed (Homebrew). Skipping."
  elif [[ -d /Applications/Tailscale.app ]]; then
    log "Tailscale already present at /Applications/Tailscale.app (not managed by Homebrew). Skipping install."
    warn "To switch to Homebrew: remove Tailscale from Applications, then re-run this script."
  else
    log "Installing Tailscale..."
    brew install --cask tailscale
    warn "Open the Tailscale app and sign in. Then re-run this script (it will skip what's done)."
  fi
fi

# ---- Docker (only if WebUI requested) ----
# Homebrew cask name is "docker" (installs Docker Desktop). Also detect a manual
# /Applications/Docker.app install so we do not run brew install into a conflict.
if [[ "$INSTALL_WEBUI" == "1" ]]; then
  if brew list --cask docker >/dev/null 2>&1; then
    log "Docker Desktop already installed (Homebrew). Skipping."
  elif [[ -d /Applications/Docker.app ]]; then
    log "Docker Desktop already present at /Applications/Docker.app (not managed by Homebrew). Skipping install."
    warn "To switch to Homebrew: quit Docker, remove the app from Applications, then re-run this script."
  else
    log "Installing Docker Desktop..."
    brew install --cask docker
    warn "Open Docker Desktop once to finish first-time setup, then re-run."
  fi
fi

# ---- Sleep / power settings ----
log "Configuring power: never sleep, allow display sleep, no disk sleep."
sudo pmset -a sleep 0 displaysleep 10 disksleep 0 || warn "pmset needs sudo; skipped."

# ---- Ollama service: bind 0.0.0.0 so LAN/Tailscale clients can reach it ----
log "Configuring Ollama to listen on 0.0.0.0:11434..."
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
brew services restart ollama
sleep 3
curl -fsS http://127.0.0.1:11434/api/tags >/dev/null \
  || die "Ollama did not start. Check: brew services info ollama"
log "Ollama is up."

# ---- Pull coding-focused models ----
if [[ "$PULL_MODELS" == "1" ]]; then
  log "Pulling coding models (this can take a while; total ~25-45 GB)..."
  ollama pull qwen2.5-coder:14b-instruct-q4_K_M
  ollama pull qwen2.5-coder:7b-base-q4_K_M
  ollama pull deepseek-coder-v2:16b-lite-instruct-q4_K_M || \
    warn "deepseek-coder-v2 16b-lite not available; skipping."
  ollama pull qwen2.5-coder:32b-instruct-q4_K_M || \
    warn "qwen2.5-coder:32b pull failed (RAM tight). Skipping."
  ollama pull codestral:22b || warn "codestral:22b not available; skipping."
  # Embedding model used by Continue.dev / Open WebUI for RAG
  ollama pull nomic-embed-text || warn "nomic-embed-text pull failed; skipping."
fi

# ---- Open WebUI (optional, browser chat UI) ----
if [[ "$INSTALL_WEBUI" == "1" ]]; then
  if ! docker info >/dev/null 2>&1; then
    warn "Docker is not running. Start Docker Desktop, then re-run with INSTALL_WEBUI=1."
  else
    if docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
      log "Open WebUI already exists; ensuring it's running."
      docker start open-webui >/dev/null
    else
      log "Starting Open WebUI on :3000..."
      docker run -d --name open-webui -p 3000:8080 \
        -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
        -v open-webui:/app/backend/data --restart always \
        ghcr.io/open-webui/open-webui:main
    fi
  fi
fi

# ---- Summary ----
TS_IP="$(/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4 2>/dev/null | head -n1 || true)"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "n/a")"

cat <<EOF

================ DONE ================
Ollama API     : http://${TS_IP:-<tailscale-ip>}:11434     (LAN: http://${LAN_IP}:11434)
Open WebUI     : http://${TS_IP:-<tailscale-ip>}:3000      (LAN: http://${LAN_IP}:3000)
Models pulled  : $(ollama list | awk 'NR>1{print $1}' | paste -sd, -)

Next on your CLIENT laptops:
  1) Install Tailscale, log in with the same account.
  2) Run setup-llm-client.sh (export SERVER_IP=${TS_IP:-<tailscale-ip>}).
  3) Open VS Code, configure Continue + Cline.

Useful:
  ollama list            # installed models
  ollama ps              # currently loaded
  ollama rm <model>      # delete a model
  brew services restart ollama
=======================================
EOF

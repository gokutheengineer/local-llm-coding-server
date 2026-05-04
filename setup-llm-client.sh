#!/usr/bin/env bash
# Local LLM client setup: VS Code + Continue + Cline + Aider, pointed at your M1 server.
# Usage:  SERVER_IP=100.x.y.z bash setup-llm-client.sh
# Works on macOS (Apple Silicon or Intel). Linux notes inline.
# Note: Docker/Open WebUI on the server is optional; this client uses Ollama API directly.

set -euo pipefail

SERVER_IP="${SERVER_IP:-}"
CHAT_MODEL="${CHAT_MODEL:-qwen2.5-coder:14b-instruct-q4_K_M}"
AUTOCOMPLETE_MODEL="${AUTOCOMPLETE_MODEL:-qwen2.5-coder:7b-base-q4_K_M}"

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }
ensure_sudo() {
  log "Requesting sudo access upfront (for smoother run)..."
  sudo -v || die "Sudo authentication failed."
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

[[ -n "$SERVER_IP" ]] || die "Set SERVER_IP env var (your M1's Tailscale IP)."

# ---- Homebrew (mac) ----
if [[ "$(uname -s)" == "Darwin" ]]; then
  ensure_sudo
  if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || \
      eval "$(/usr/local/bin/brew shellenv)"
  else
    log "Homebrew already installed."
  fi

  # Casks: skip brew install if the app already exists outside Homebrew (avoids "already an App" errors).
  if brew list --cask tailscale >/dev/null 2>&1; then
    log "Tailscale already installed (Homebrew)."
    brew upgrade --cask tailscale || true
  elif [[ -d /Applications/Tailscale.app ]]; then
    log "Tailscale already present at /Applications/Tailscale.app (not managed by Homebrew). Skipping install."
    warn "To switch to Homebrew: remove Tailscale from Applications, then re-run this script."
  else
    log "Installing Tailscale..."
    brew install --cask tailscale
  fi

  if brew list --cask visual-studio-code >/dev/null 2>&1; then
    log "Visual Studio Code already installed (Homebrew)."
    brew upgrade --cask visual-studio-code || true
  elif [[ -d "/Applications/Visual Studio Code.app" ]]; then
    log "Visual Studio Code already in /Applications (not managed by Homebrew). Skipping install."
    warn "To switch to Homebrew: remove Visual Studio Code from Applications, then re-run."
  else
    log "Installing Visual Studio Code..."
    brew install --cask visual-studio-code
  fi

  log "Ensuring python, git, pipx..."
  brew install python git pipx
  brew upgrade python git pipx || true
fi

# ---- Connectivity check ----
log "Pinging Ollama at http://${SERVER_IP}:11434 ..."
if ! curl -fsS "http://${SERVER_IP}:11434/api/tags" >/dev/null; then
  die "Cannot reach server. Is Tailscale connected on both ends?"
fi
log "Server reachable."

# ---- Continue.dev config ----
CONT_DIR="$HOME/.continue"
mkdir -p "$CONT_DIR"
cat > "$CONT_DIR/config.json" <<JSON
{
  "models": [
    {
      "title": "Qwen2.5 Coder 14B (M1)",
      "provider": "ollama",
      "model": "${CHAT_MODEL}",
      "apiBase": "http://${SERVER_IP}:11434"
    },
    {
      "title": "Qwen2.5 Coder 32B (M1, slow)",
      "provider": "ollama",
      "model": "qwen2.5-coder:32b-instruct-q4_K_M",
      "apiBase": "http://${SERVER_IP}:11434"
    },
    {
      "title": "DeepSeek Coder V2 Lite (fast)",
      "provider": "ollama",
      "model": "deepseek-coder-v2:16b-lite-instruct-q4_K_M",
      "apiBase": "http://${SERVER_IP}:11434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen 7B Autocomplete",
    "provider": "ollama",
    "model": "${AUTOCOMPLETE_MODEL}",
    "apiBase": "http://${SERVER_IP}:11434"
  },
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "nomic-embed-text",
    "apiBase": "http://${SERVER_IP}:11434"
  },
  "allowAnonymousTelemetry": false
}
JSON
log "Wrote ${CONT_DIR}/config.json"

# ---- VS Code extensions ----
if command -v code >/dev/null 2>&1; then
  log "Installing VS Code extensions: Continue, Cline..."
  code --install-extension Continue.continue --force
  code --install-extension saoudrizwan.claude-dev --force   # Cline
else
  warn "'code' CLI not found. In VS Code: Cmd+Shift+P -> 'Shell Command: Install code command in PATH'."
fi

# ---- Aider (terminal agent) ----
if command -v pipx >/dev/null 2>&1; then
  if pipx list --short 2>/dev/null | grep -qE '^aider-chat([[:space:]]|$)'; then
    log "Upgrading aider-chat (pipx)..."
    pipx upgrade aider-chat || true
  else
    log "Installing aider-chat (pipx)..."
    pipx install aider-chat
  fi
else
  log "Installing aider-chat via pip (user)..."
  python3 -m pip install --user --upgrade aider-chat
fi

# Convenience launcher for Aider pointing to your server
AIDER_BIN="$HOME/.local/bin/aider-local"
mkdir -p "$HOME/.local/bin"
cat > "$AIDER_BIN" <<SH
#!/usr/bin/env bash
export OLLAMA_API_BASE="http://${SERVER_IP}:11434"
exec aider --model "ollama/${CHAT_MODEL}" --no-show-model-warnings "\$@"
SH
chmod +x "$AIDER_BIN"

cat <<EOF

================ CLIENT READY ================
Continue config : ~/.continue/config.json   (Cmd+L chat, Cmd+I inline, Tab autocomplete)
Cline           : VS Code -> Cline icon -> Settings:
                    API Provider: Ollama
                    Base URL:     http://${SERVER_IP}:11434
                    Model:        ${CHAT_MODEL}
Aider           : run 'aider-local' in any git repo
                  or:  OLLAMA_API_BASE=http://${SERVER_IP}:11434 aider --model ollama/${CHAT_MODEL}

Tip: open ~/.continue/config.json to switch between 14B / 32B / DeepSeek.
==============================================
EOF

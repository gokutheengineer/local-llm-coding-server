#!/usr/bin/env bash
# Install local-LLM coding clients on a laptop:
# - Tailscale
# - VS Code (and Cursor if INSTALL_CURSOR=1)
# - Continue + Cline extensions
# - Aider terminal agent
#
# Usage:
#   bash install-coding-tools.sh
#   SERVER_IP=100.x.y.z bash install-coding-tools.sh   # also writes Continue/Aider config
#
# Env:
#   SERVER_IP=100.x.y.z
#   CHAT_MODEL=qwen2.5-coder:14b-instruct-q4_K_M
#   AUTOCOMPLETE_MODEL=qwen2.5-coder:7b-base-q4_K_M
#   INSTALL_CURSOR=0

set -euo pipefail

SERVER_IP="${SERVER_IP:-}"
CHAT_MODEL="${CHAT_MODEL:-qwen2.5-coder:14b-instruct-q4_K_M}"
AUTOCOMPLETE_MODEL="${AUTOCOMPLETE_MODEL:-qwen2.5-coder:7b-base-q4_K_M}"
INSTALL_CURSOR="${INSTALL_CURSOR:-0}"

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }

ensure_sudo() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "Requesting sudo access upfront..."
    sudo -v || die "Sudo authentication failed."
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  fi
}

install_cask_if_missing() {
  local cask="$1"
  local app_path="$2"
  local label="$3"

  if brew list --cask "$cask" >/dev/null 2>&1; then
    log "$label already installed (Homebrew). Skipping."
  elif [[ -d "$app_path" ]]; then
    log "$label already exists at $app_path. Skipping Homebrew install."
  else
    log "Installing $label..."
    brew install --cask "$cask"
  fi
}

install_formula_if_missing() {
  local formula="$1"

  if brew list --formula "$formula" >/dev/null 2>&1; then
    log "$formula already installed. Skipping."
  else
    log "Installing $formula..."
    brew install "$formula"
  fi
}

install_vscode_extensions() {
  local cli
  local ext
  local installed_any=0

  for cli in code cursor; do
    if command -v "$cli" >/dev/null 2>&1; then
      installed_any=1
      log "Checking Continue + Cline extensions via '$cli'..."
      for ext in Continue.continue saoudrizwan.claude-dev; do
        if "$cli" --list-extensions | grep -qx "$ext"; then
          log "$ext already installed for $cli. Skipping."
        else
          log "Installing $ext for $cli..."
          "$cli" --install-extension "$ext" || warn "$ext install failed for $cli."
        fi
      done
    fi
  done

  if [[ "$installed_any" == "0" ]]; then
    warn "No 'code' or 'cursor' CLI found."
    warn "In VS Code/Cursor: Cmd+Shift+P -> Shell Command: Install command in PATH, then re-run."
  fi
}

write_continue_config() {
  [[ -n "$SERVER_IP" ]] || return 0

  local cont_dir="$HOME/.continue"
  mkdir -p "$cont_dir"

  cat > "$cont_dir/config.json" <<JSON
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

  log "Wrote ${cont_dir}/config.json"
}

install_aider() {
  if command -v pipx >/dev/null 2>&1; then
    if pipx list --short 2>/dev/null | grep -qE '^aider-chat([[:space:]]|$)'; then
      log "aider-chat already installed (pipx). Skipping."
    else
      log "Installing aider-chat (pipx)..."
      pipx install aider-chat
    fi
    pipx ensurepath || true
  elif command -v aider >/dev/null 2>&1; then
    log "aider already available on PATH. Skipping install."
  else
    log "Installing aider-chat via pip (user)..."
    python3 -m pip install --user aider-chat
  fi
}

write_aider_launcher() {
  [[ -n "$SERVER_IP" ]] || return 0

  local aider_bin="$HOME/.local/bin/aider-local"
  mkdir -p "$HOME/.local/bin"

  cat > "$aider_bin" <<SH
#!/usr/bin/env bash
export OLLAMA_API_BASE="http://${SERVER_IP}:11434"
exec aider --model "ollama/${CHAT_MODEL}" --no-show-model-warnings "\$@"
SH
  chmod +x "$aider_bin"
  log "Wrote $aider_bin"
}

ensure_sudo

if [[ "$(uname -s)" == "Darwin" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || \
      eval "$(/usr/local/bin/brew shellenv)"
  else
    log "Homebrew already installed."
  fi

  install_cask_if_missing tailscale /Applications/Tailscale.app "Tailscale"
  install_cask_if_missing visual-studio-code "/Applications/Visual Studio Code.app" "Visual Studio Code"
  if [[ "$INSTALL_CURSOR" == "1" ]]; then
    install_cask_if_missing cursor /Applications/Cursor.app "Cursor"
  fi

  log "Ensuring python, git, pipx, jq..."
  for formula in python git pipx jq; do
    install_formula_if_missing "$formula"
  done
else
  warn "Non-macOS detected. Install Tailscale, VS Code/Cursor, python3, git, pipx manually if needed."
fi

install_vscode_extensions
install_aider
write_continue_config
write_aider_launcher

cat <<EOF

================ CODING TOOLS READY ================
Installed/configured:
  - Tailscale
  - VS Code/Cursor extensions: Continue + Cline (if CLI was available)
  - Aider terminal agent
  - ~/.continue/config.json (only if SERVER_IP was provided)
  - ~/.local/bin/aider-local (only if SERVER_IP was provided)

Next:
  SERVER_IP=${SERVER_IP:-100.x.y.z} bash check-llm-connection.sh

Use:
  cd /path/to/git-repo && aider-local
  VS Code/Cursor -> Cline -> Provider: Ollama, Base URL: http://${SERVER_IP:-100.x.y.z}:11434
====================================================
EOF

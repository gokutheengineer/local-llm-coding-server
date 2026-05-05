#!/usr/bin/env bash
# Smoke-test the client -> server -> model path.
#
# Usage:
#   SERVER_IP=100.x.y.z bash check-llm-connection.sh
#
# Env:
#   SERVER_IP=100.x.y.z
#   MODEL=qwen2.5-coder:14b-instruct-q4_K_M
#   TIMEOUT_SECONDS=180

set -euo pipefail

SERVER_IP="${SERVER_IP:-}"
MODEL="${MODEL:-qwen2.5-coder:14b-instruct-q4_K_M}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }

[[ -n "$SERVER_IP" ]] || die "Set SERVER_IP env var (example: SERVER_IP=100.x.y.z bash check-llm-connection.sh)."

BASE_URL="http://${SERVER_IP}:11434"

log "Checking Ollama tags endpoint: ${BASE_URL}/api/tags"
tags_json="$(curl -fsS --max-time 15 "${BASE_URL}/api/tags")" \
  || die "Cannot reach Ollama. Check Tailscale, server IP, and OLLAMA_HOST=0.0.0.0:11434."

if command -v jq >/dev/null 2>&1; then
  model_names="$(printf '%s' "$tags_json" | jq -r '.models[]?.name' 2>/dev/null || true)"
else
  model_names="$(printf '%s' "$tags_json" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
fi

if [[ -z "$model_names" ]]; then
  warn "Ollama is reachable, but no models were returned."
  warn "Run on server: ollama pull ${MODEL}"
else
  log "Models visible from client:"
  printf '%s\n' "$model_names" | sed 's/^/  - /'
fi

if ! printf '%s\n' "$model_names" | grep -qx "$MODEL"; then
  warn "Requested model '${MODEL}' was not found in /api/tags."
  warn "Generation test may fail unless Ollama can auto-pull it. Pull it on the server first:"
  warn "  ollama pull ${MODEL}"
fi

payload="$(cat <<JSON
{
  "model": "${MODEL}",
  "prompt": "Return only a tiny Swift function named add that adds two Int values.",
  "stream": false,
  "options": {
    "temperature": 0,
    "num_predict": 80
  }
}
JSON
)"

log "Running generation test with model: ${MODEL}"
response_json="$(curl -fsS --max-time "$TIMEOUT_SECONDS" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "${BASE_URL}/api/generate")" \
  || die "Generation failed. If this is first run, model may still be loading or missing on server."

if command -v jq >/dev/null 2>&1; then
  generated="$(printf '%s' "$response_json" | jq -r '.response // empty')"
else
  generated="$(printf '%s' "$response_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("response",""))' 2>/dev/null || true)"
fi

[[ -n "$generated" ]] || die "Generation response was empty."

cat <<EOF

================ LLM CONNECTION OK ================
Server       : ${BASE_URL}
Model        : ${MODEL}
API tags     : OK
Generation   : OK

Model response:
---------------------------------------------------
${generated}
---------------------------------------------------

Next:
  - Cline Base URL: ${BASE_URL}
  - Cline Model   : ${MODEL}
  - Terminal      : cd /path/to/repo && aider-local
===================================================
EOF

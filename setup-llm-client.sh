#!/usr/bin/env bash
# One-command client setup:
# 1) install/configure coding tools (Continue, Cline, Aider)
# 2) smoke-test client -> server -> model generation
#
# Usage:
#   SERVER_IP=100.x.y.z bash setup-llm-client.sh

set -euo pipefail

SERVER_IP="${SERVER_IP:-}"
CHAT_MODEL="${CHAT_MODEL:-qwen2.5-coder:14b-instruct-q4_K_M}"

die() { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }
[[ -n "$SERVER_IP" ]] || die "Set SERVER_IP env var (your M1's Tailscale IP)."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_IP="$SERVER_IP" CHAT_MODEL="$CHAT_MODEL" bash "$SCRIPT_DIR/install-coding-tools.sh"
SERVER_IP="$SERVER_IP" MODEL="$CHAT_MODEL" bash "$SCRIPT_DIR/check-llm-connection.sh"

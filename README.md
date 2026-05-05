# Local LLM Coding Server

Self-hosted, coding-focused LLM stack for an Apple Silicon Mac (M1/M2/M3, 32 GB RAM)
that you access from other laptops over [Tailscale](https://tailscale.com/).

The goal is a **private, local "Claude Code / Cursor" replacement** with no chat
fluff — just IDE autocomplete, inline edits, and agentic coding.

## Stack

- **Ollama** — model runtime + OpenAI-compatible REST API (`:11434`)
- **Open WebUI** *(optional)* — browser chat UI on `:3000`
- **Tailscale** — secure remote access from any laptop
- **Coder models** (pulled by default):
  - `qwen2.5-coder:14b-instruct-q4_K_M` — primary chat/agent (recommended)
  - `qwen2.5-coder:7b-base-q4_K_M` — Tab autocomplete (FIM)
  - `deepseek-coder-v2:16b-lite-instruct-q4_K_M` — fast MoE alternative
  - `qwen2.5-coder:32b-instruct-q4_K_M` — high quality, slow on 32 GB
  - `codestral:22b` — strong FIM autocomplete
- **Client tools**: VS Code + Continue.dev (chat / inline / autocomplete),
  Cline (agent), Aider (terminal git-aware agent)

## Architecture

```
[Other laptop]  ->  VS Code + Continue/Cline    \
[Other laptop]  ->  Browser + Open WebUI        \--> [M1 Mac: Ollama :11434]
[Phone/iPad]    ->  Browser + Open WebUI        /          (Metal GPU)
                          (Tailscale VPN)
```

## Server setup (run on the M1 Mac)

```bash
git clone https://github.com/gokutheengineer/local-llm-coding-server.git
cd local-llm-coding-server
bash setup-llm-server.sh
```

Toggles:

```bash
INSTALL_WEBUI=1     bash setup-llm-server.sh   # install/start Open WebUI (Docker)
INSTALL_TAILSCALE=0 bash setup-llm-server.sh  # skip Tailscale install
PULL_MODELS=0      bash setup-llm-server.sh   # skip model downloads
```

Default behavior: Open WebUI/Docker steps are skipped unless you explicitly set
`INSTALL_WEBUI=1`.

After it finishes, sign into Tailscale (GUI), then note your Tailscale IP:

```bash
tailscale ip -4
```

## Client setup (run on each other laptop)

Install Tailscale first and sign in with the same account.

```bash
git clone https://github.com/gokutheengineer/local-llm-coding-server.git
cd local-llm-coding-server
SERVER_IP=100.x.y.z bash setup-llm-client.sh
```

This one command will:

- Install VS Code, Tailscale, pipx, Python (mac)
- Install VS Code/Cursor extensions: **Continue**, **Cline** when the CLI is available
- Write `~/.continue/config.json` pointed at your server
- Install **Aider** and create an `aider-local` launcher
- Run a real smoke test: client -> Ollama API -> coder model generation

If you only want to install the coding tools without running the generation test:

```bash
SERVER_IP=100.x.y.z bash install-coding-tools.sh
```

If you already installed everything and only want to verify the server connection:

```bash
SERVER_IP=100.x.y.z bash check-llm-connection.sh
```

That script checks:

- `http://<server-ip>:11434/api/tags` returns models
- the selected model can generate a tiny Swift function
- the same base URL is ready for Cline, Continue, and Aider

## Daily usage

- **Continue (VS Code)**: `Cmd+L` chat, `Cmd+I` inline edit, Tab autocomplete
- **Cline (VS Code)**: agentic file edits + terminal commands (closest to Claude Code)
- **Aider (terminal)**: `cd repo && aider-local` — git-aware multi-file edits
- **Open WebUI**: `http://<tailscale-ip>:3000` for chat / RAG / file uploads

For coding automation, start here:

```bash
cd /path/to/your/git-repo
aider-local
```

Then type normal requests:

```text
Inspect this repo, find the likely cause of the failing tests, fix only the needed files, and run the relevant test command.
```

For Cline, use:

```text
Provider: Ollama
Base URL: http://100.x.y.z:11434
Model: qwen2.5-coder:14b-instruct-q4_K_M
```

## Switching models

```bash
ollama list
ollama pull <model>
ollama rm   <model>
```

Then update the `model` field in `~/.continue/config.json` on the client,
or pick from the model dropdown inside Cline / Continue.

## Performance notes (M1 32 GB, q4_K_M)

| Model | Tokens/sec | Use |
|---|---|---|
| 7B  | 40-60 | autocomplete |
| 14B | 15-25 | chat / agent |
| 32B | 5-10  | quality but slow |

## Troubleshooting

- `curl http://<ip>:11434/api/tags` should return JSON. If not, Tailscale is down
  or `OLLAMA_HOST` is not bound to `0.0.0.0`.
- Run `SERVER_IP=100.x.y.z bash check-llm-connection.sh` from the client for a full API + generation test.
- `launchctl setenv OLLAMA_HOST "0.0.0.0:11434" && brew services restart ollama`
- Keep the Mac awake: `sudo pmset -a sleep 0 disksleep 0`
- Free a stuck model: `ollama stop <model>`

## License

MIT

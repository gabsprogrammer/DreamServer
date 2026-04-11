# Mobile Shell Preview

Last updated: 2026-04-11

## What this is

Dream Server now has a first-pass mobile shell preview for:

- **Android / Termux**
- **iOS / a-Shell**

This path is intentionally small:

- it does **not** start the full Docker stack
- it does **not** enable dashboard, voice, workflows, agents, or RAG
- it **does** keep the interface shell-first
- it **does** provide a stable CLI contract for future local runtimes
- it **does** expose an intent-style bridge for Apple Shortcuts on iOS

## Current mobile target

### Android / Termux

Supported preview flow:

```bash
git clone https://github.com/gabsprogrammer/DreamServer.git
cd DreamServer
./install.sh
./dream-mobile.sh chat
```

What the installer does on Termux:

1. Detects that the shell is Termux.
2. Installs build dependencies with `pkg`.
3. Clones and builds `llama.cpp`.
4. Downloads the official GGUF build of `Qwen3-0.6B`.
5. Writes `.dream-mobile.env` so `./dream-mobile.sh` can run the model later.

Current default model:

- Repo: `ggml-org/Qwen3-0.6B-GGUF`
- File: `Qwen3-0.6B-Q4_0.gguf`

Useful commands:

```bash
./dream-mobile.sh status
./dream-mobile.sh chat
./dream-mobile.sh prompt "me resume este projeto"
```

## iOS / a-Shell

a-Shell now has a **CLI + Shortcuts preview path**.

What works today:

- `sh ./install.sh` sets up the iOS preview files and downloads `Qwen3-0.6B` by default
- `sh ./dream-mobile.sh intent "abrir calculadora"` returns JSON for Apple Shortcuts
- `sh ./dream-mobile.sh prompt "abrir safari no github"` uses the same routing contract
- `sh ./dream-mobile.sh apps` lists the stable `app_id` values to route inside Shortcuts

Current engine behavior:

- default engine: local rule-based intent router
- optional future engine: local `wasm` llama runtime if you drop it into the expected path
- full Dream Server service graph: still out of scope for iOS shell mode

Example flow:

```bash
sh ./install.sh
sh ./dream-mobile.sh status
sh ./dream-mobile.sh intent "abrir calculadora"
sh ./dream-mobile.sh prompt "abrir safari no github"
```

The `prompt` and `intent` commands are intentionally compatible with a future local runtime:

- if a local wasm backend is present, `prompt` can use it
- if not, `prompt` falls back to the local intent router so the Shortcut loop still works

Shortcut setup guidance lives in [IOS-ASHELL-SHORTCUTS.md](IOS-ASHELL-SHORTCUTS.md).

## Scope guardrail

This mobile preview is meant for **testing the mobile control loop first**:

- platform detection
- local shell command contract
- app-routing intents
- Shortcut integration

It is **not** yet the mobile version of full Dream Server.

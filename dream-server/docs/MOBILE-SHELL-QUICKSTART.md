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
- it **does** let Android export generated files into shared storage when available

## Current mobile target

### Android / Termux

Supported preview flow:

```bash
git clone https://github.com/gabsprogrammer/DreamServer.git
cd DreamServer
termux-setup-storage
./install.sh
./dream-mobile.sh local
./dream-mobile.sh chat
```

What the installer does on Termux:

1. Detects that the shell is Termux.
2. Installs build dependencies with `pkg`.
3. Clones and builds the minimal `llama.cpp` binaries needed for local mobile chat.
4. Downloads the official GGUF build of `Qwen3-0.6B`.
5. Detects whether shared Android storage is available through `~/storage/downloads`.
6. Writes `.dream-mobile.env` so `./dream-mobile.sh` can run the model later.

Current default model:

- Repo: `ggml-org/Qwen3-0.6B-GGUF`
- File: `Qwen3-0.6B-Q4_0.gguf`

Useful commands:

```bash
./dream-mobile.sh status
./dream-mobile.sh local
./dream-mobile.sh chat
./dream-mobile.sh prompt "me resume este projeto"
./dream-mobile.sh export notes/brief.txt "gere um resumo claro deste repo"
```

Android localhost UI:

- `./dream-mobile.sh local` starts a small local web server on `127.0.0.1:8765`
- if `termux-open-url` is available, Dream Server opens the page in your browser automatically
- the page keeps the Android preview focused on one thing: local chat plus live device status

Android export behavior:

- if `termux-setup-storage` has already been granted, `export` writes into shared Downloads
- if shared storage is not configured yet, Dream Server falls back to `data/exports/mobile/` inside the repo
- rerun `./install.sh` after granting storage permission so the mobile config points at Downloads

If the install fails with `curl`, `git`, or `libnghttp2` symbol errors:

```bash
apt update && apt full-upgrade
termux-change-repo
./install.sh
```

That usually means the Termux userland is in a partial-upgrade state, not that the Dream Server installer itself is broken.

## iOS / a-Shell

iOS is now a **lite beta** focused on local shell chat only.

What works today:

- `sh ./install.sh` sets up the iOS preview files and downloads `Qwen3-0.6B` by default
- `sh ./dream-mobile.sh status` shows whether the model and wasm runtime slot are ready
- `sh ./dream-mobile.sh chat` starts the local interactive chat loop

Example flow:

```bash
lg2 clone https://github.com/gabsprogrammer/DreamServer.git
cd DreamServer
sh ./install.sh
sh ./dream-mobile.sh status
sh ./dream-mobile.sh chat
```

The iPhone path is intentionally narrow:

- no full Docker stack
- no dashboard, workflows, or agents
- no desktop feature parity yet

Focused setup guidance lives in [IOS-ASHELL-SHORTCUTS.md](IOS-ASHELL-SHORTCUTS.md).

## Scope guardrail

This mobile preview is meant for **testing the mobile control loop first**:

- platform detection
- local shell command contract
- app-routing intents
- Shortcut integration

It is **not** yet the mobile version of full Dream Server.

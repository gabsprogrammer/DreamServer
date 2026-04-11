# Mobile Shell Preview

Last updated: 2026-04-11

## What this is

Dream Server now has a first-pass mobile shell preview for **Android / Termux**.

This path is intentionally small:

- it does **not** start the full Docker stack
- it does **not** enable dashboard, voice, workflows, agents, or RAG
- it **does** build a local `llama.cpp` CLI runtime
- it **does** download a small local model and let you chat with it from the shell

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

a-Shell is now detected explicitly, but the local shell preview stops there for now.

Why:

- a-Shell runs C/C++ shell programs as WebAssembly.
- the current Dream Server mobile preview depends on a native `llama.cpp` CLI runtime.
- the full Dream Server stack is also out of scope for iOS shell mode.

Result:

- Android / Termux: preview works
- iOS / a-Shell: detected cleanly, then blocked with a clear message

## Scope guardrail

This mobile preview is meant for **testing the local shell flow first**.

It is the right place to prove:

- platform detection
- lightweight model bootstrap
- shell chat UX

It is **not** yet the mobile version of full Dream Server.

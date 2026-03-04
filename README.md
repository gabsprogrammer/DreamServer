<div align="center">

# Dream Server

### One command to a full local AI stack.

**LLM inference, chat UI, voice agents, workflow automation, RAG, image generation, and privacy tools — all running on your hardware. No cloud. No subscriptions. No configuration.**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/Light-Heart-Labs/DreamServer)](https://github.com/Light-Heart-Labs/DreamServer/stargazers)
[![Release](https://img.shields.io/github/v/release/Light-Heart-Labs/DreamServer)](https://github.com/Light-Heart-Labs/DreamServer/releases)

![Dream Server Dashboard](docs/images/dashboard.png)

[![Watch the demo](https://img.shields.io/badge/Demo-Watch%20on%20YouTube-red?logo=youtube)](https://youtu.be/nO8xFNHX-HA)

</div>

---

## Why Dream Server?

Setting up local AI usually means stitching together a dozen projects, debugging CUDA drivers, writing Docker configs, and hoping everything talks to each other. Dream Server replaces all of that with a single installer.

- **Run one command** — the installer detects your GPU, picks the right model for your hardware, generates secure credentials, and launches everything
- **Chat in under 2 minutes** — bootstrap mode starts a small model instantly while your full model downloads in the background
- **13 integrated services** — chat, agents, voice, workflows, search, RAG, image generation, and more, all pre-wired and working together
- **Fully moddable** — drop in a folder, run `dream enable`, done. Every service is an extension

```bash
curl -fsSL https://raw.githubusercontent.com/Light-Heart-Labs/DreamServer/main/dream-server/get-dream-server.sh | bash
```

Open **http://localhost:3000** and start chatting.

<div align="center">

![Dream Server Installer](docs/images/installer-splash.gif)

*The DREAMGATE installer handles everything — GPU detection, model selection, service orchestration.*

</div>

<details>
<summary><b>Manual install / Windows</b></summary>

**Linux / WSL:**
```bash
git clone https://github.com/Light-Heart-Labs/DreamServer.git
cd DreamServer/dream-server
./install.sh
```

**Windows (PowerShell):**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Light-Heart-Labs/DreamServer/main/install.ps1" -OutFile install.ps1
.\install.ps1
```

Windows installer checks prerequisites (WSL2, Docker, NVIDIA drivers), then delegates to the Linux install path.

</details>

---

## What You Get

### Chat & Inference
- **Open WebUI** — full-featured chat interface with conversation history, web search, and document upload
- **llama-server** — high-performance LLM inference with continuous batching, auto-selected for your GPU
- **LiteLLM** — API gateway supporting local/cloud/hybrid modes

### Voice
- **Whisper** — speech-to-text
- **Kokoro** — text-to-speech

### Agents & Automation
- **OpenClaw** — autonomous AI agent framework
- **n8n** — workflow automation with 400+ integrations (Slack, email, databases, APIs)

### Knowledge & Search
- **Qdrant** — vector database for retrieval-augmented generation (RAG)
- **SearXNG** — self-hosted web search (no tracking)
- **Perplexica** — deep research engine

### Creative
- **ComfyUI** — node-based image generation

### Privacy & Ops
- **Privacy Shield** — PII scrubbing proxy for API calls
- **Dashboard** — real-time GPU metrics, service health, model management

---

## Hardware Auto-Detection

The installer detects your GPU and picks the optimal model automatically. No manual configuration.

### NVIDIA

| VRAM | Model | Example GPUs |
|------|-------|--------------|
| 8–11 GB | Qwen 2.5 7B (Q4_K_M) | RTX 4060 Ti, RTX 3060 12GB |
| 12–20 GB | Qwen 2.5 14B (Q4_K_M) | RTX 3090, RTX 4080 |
| 20–40 GB | Qwen 2.5 32B (Q4_K_M) | RTX 4090, A6000 |
| 40+ GB | Qwen 2.5 72B (Q4_K_M) | A100, multi-GPU |
| 90+ GB | Qwen3 Coder Next 80B MoE | Multi-GPU A100/H100 |

### AMD Strix Halo (Unified Memory)

| Unified RAM | Model | Hardware |
|-------------|-------|----------|
| 64–89 GB | Qwen3 30B-A3B (30B MoE) | Ryzen AI MAX+ 395 (64GB) |
| 90+ GB | Qwen3 Coder Next (80B MoE) | Ryzen AI MAX+ 395 (96GB) |

Override tier selection: `./install.sh --tier 3`

---

## Bootstrap Mode

No staring at download bars. Dream Server uses bootstrap mode by default:

1. Downloads a tiny 1.5B model in under a minute
2. You start chatting immediately
3. The full model downloads in the background
4. Hot-swap to the full model when it's ready — zero downtime

<div align="center">

![Installer downloading modules](docs/images/installer-download.png)

*The installer pulls all services in parallel — "Take a break for ten minutes. I've got this."*

</div>

Skip bootstrap: `./install.sh --no-bootstrap`

---

## Extensibility

Dream Server is designed to be modded. Every service is an extension — a folder with a `manifest.yaml` and a `compose.yaml`. The dashboard, CLI, health checks, and compose stack all discover extensions automatically.

```
extensions/services/
  my-service/
    manifest.yaml      # Metadata: name, port, health endpoint, GPU backends
    compose.yaml       # Docker Compose fragment (auto-merged into the stack)
```

```bash
dream enable my-service     # Enable it
dream disable my-service    # Disable it
dream list                  # See everything
```

The installer itself is modular — 6 libraries and 13 phases, each in its own file. Want to add a hardware tier, swap a default model, or skip a phase? Edit one file.

[Full extension guide](dream-server/docs/EXTENSIONS.md) | [Installer architecture](dream-server/docs/INSTALLER-ARCHITECTURE.md)

---

## dream-cli

The `dream` CLI manages your entire stack:

```bash
dream status                # Health checks + GPU status
dream list                  # All services and their state
dream logs llm              # Tail logs (aliases: llm, stt, tts)
dream restart [service]     # Restart one or all services
dream start / stop          # Start or stop the stack

dream mode cloud            # Switch to cloud APIs via LiteLLM
dream mode local            # Switch back to local inference
dream mode hybrid           # Local primary, cloud fallback

dream model swap T3         # Switch to a different hardware tier
dream enable n8n            # Enable an extension
dream disable whisper       # Disable one

dream config show           # View .env (secrets masked)
dream preset save gaming    # Snapshot current config
dream preset load gaming    # Restore it
```

---

## How It Compares

| | Dream Server | Ollama + Open WebUI | LocalAI |
|---|:---:|:---:|:---:|
| One-command full-stack install | LLM + agents + workflows + RAG + voice + images | LLM + chat only | LLM only |
| Hardware auto-detect + model selection | NVIDIA + AMD Strix Halo | No | No |
| AMD APU unified memory support | ROCm + llama-server | Partial (Vulkan) | No |
| Autonomous AI agents | OpenClaw | No | No |
| Workflow automation | n8n (400+ integrations) | No | No |
| Voice (STT + TTS) | Whisper + Kokoro | No | No |
| Image generation | ComfyUI | No | No |
| RAG pipeline | Qdrant + embeddings | No | No |
| Extension system | Manifest-based, hot-pluggable | No | No |
| Multi-GPU | Yes (NVIDIA) | Partial | Partial |

---

## Documentation

| | |
|---|---|
| [Quickstart](dream-server/QUICKSTART.md) | Step-by-step install guide with troubleshooting |
| [Hardware Guide](dream-server/docs/HARDWARE-GUIDE.md) | What to buy, tier recommendations |
| [FAQ](dream-server/FAQ.md) | Common questions and configuration |
| [Extensions](dream-server/docs/EXTENSIONS.md) | How to add custom services |
| [Installer Architecture](dream-server/docs/INSTALLER-ARCHITECTURE.md) | Modular installer deep dive |
| [Changelog](dream-server/CHANGELOG.md) | Version history and release notes |
| [Contributing](CONTRIBUTING.md) | How to contribute |

---

## Acknowledgments

Dream Server exists because of the incredible people, projects, and communities that make open-source AI possible. We are grateful to every contributor, maintainer, and tinkerer whose work powers this stack.

Thanks to [kyuz0](https://github.com/kyuz0) for [amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) — pre-built ROCm containers for Strix Halo that saved us a lot of pain from having to build our own. And to [lhl](https://github.com/lhl) for [strix-halo-testing](https://github.com/lhl/strix-halo-testing) — the foundational Strix Halo AI research and rocWMMA performance work that the broader community builds on.

### Projects that make Dream Server possible

*   [llama.cpp (ggerganov)](https://github.com/ggml-org/llama.cpp) — LLM inference engine
*   [Qwen (Alibaba Cloud)](https://github.com/QwenLM/Qwen) — Default language models
*   [Open WebUI](https://github.com/open-webui/open-webui) — Chat interface
*   [ComfyUI](https://github.com/comfyanonymous/ComfyUI) — Image generation engine
*   [FLUX.1 (Black Forest Labs)](https://github.com/black-forest-labs/flux) — Image generation model
*   [AMD ROCm](https://github.com/ROCm/ROCm) — GPU compute platform
*   [AMD Strix Halo Toolboxes (kyuz0)](https://github.com/kyuz0/amd-strix-halo-toolboxes) — Pre-built ROCm containers for AMD inference
*   [Strix Halo Testing (lhl)](https://github.com/lhl/strix-halo-testing) — Foundational Strix Halo AI research and rocWMMA optimizations
*   [n8n](https://github.com/n8n-io/n8n) — Workflow automation
*   [Qdrant](https://github.com/qdrant/qdrant) — Vector database
*   [SearXNG](https://github.com/searxng/searxng) — Privacy-respecting search
*   [Perplexica](https://github.com/ItzCrazyKns/Perplexica) — AI-powered search
*   [LiteLLM](https://github.com/BerriAI/litellm) — LLM API gateway
*   [Kokoro FastAPI (remsky)](https://github.com/remsky/Kokoro-FastAPI) — Text-to-speech
*   [Speaches](https://github.com/speaches-ai/speaches) — Speech-to-text
*   [Strix Halo Home Lab](https://strixhalo-homelab.d7.wtf/) — Community knowledge base

If we missed anyone, [open an issue](https://github.com/Light-Heart-Labs/DreamServer/issues). We want to get this right.

---

## License

Apache 2.0 — Use it, modify it, ship it. See [LICENSE](LICENSE).

---

<div align="center">

*Built by [Light Heart Labs](https://github.com/Light-Heart-Labs) and [The Collective](https://github.com/Light-Heart-Labs/DreamServer)*

</div>

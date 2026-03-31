# Research

Technical research and benchmarks from building a local AI stack on consumer hardware. Real-world findings from production deployments, not theoretical estimates.

**88 documents across 7 categories.**

---

## Categories

### [`agent-systems/`](agent-systems/) — Agent Architecture Blueprint (32 docs)

**Start here:** [`AGENT-ARCHITECTURE-OVERVIEW.md`](agent-systems/AGENT-ARCHITECTURE-OVERVIEW.md)

Complete, vendor-neutral blueprint for building a production agentic coding tool from scratch. 32 documents, 14,384 lines, organized in 7 architectural layers — from security foundations to the execution engine. Includes a [local LLM adaptation guide](agent-systems/AGENT-LOCAL-LLM-ADAPTATION.md) bridging all patterns to DreamServer's local stack.

See [`agent-systems/README.md`](agent-systems/README.md) for the full reading order.

---

### [`hardware/`](hardware/) — GPU Hardware & Capacity (12 docs)

| Document | What It Covers |
|----------|---------------|
| [HARDWARE-GUIDE.md](hardware/HARDWARE-GUIDE.md) | GPU buying guide — tiers, prices, what NOT to buy, used market |
| [gpu-hardware-guide-2026.md](hardware/gpu-hardware-guide-2026.md) | 2026 GPU recommendations and pricing |
| [M6-HARDWARE-BUYING-GUIDE-2026.md](hardware/M6-HARDWARE-BUYING-GUIDE-2026.md) | Milestone 6 hardware buying analysis |
| [M6-CONSUMER-GPU-BENCHMARKS-2026-02-09.md](hardware/M6-CONSUMER-GPU-BENCHMARKS-2026-02-09.md) | Consumer GPU inference benchmarks |
| [M6-MINIMUM-HARDWARE.md](hardware/M6-MINIMUM-HARDWARE.md) | Minimum hardware requirements per tier |
| [M6-VRAM-MULTI-SERVICE-LIMITS.md](hardware/M6-VRAM-MULTI-SERVICE-LIMITS.md) | VRAM budgets for running multiple AI services |
| [SINGLE-GPU-MULTI-SERVICE.md](hardware/SINGLE-GPU-MULTI-SERVICE.md) | Full stack on a single GPU |
| [M8-CAPACITY-BASELINE-2026-02-09.md](hardware/M8-CAPACITY-BASELINE-2026-02-09.md) | Capacity baselines and load testing |
| [CLUSTER-BENCHMARKS-2026-02-10.md](hardware/CLUSTER-BENCHMARKS-2026-02-10.md) | Multi-GPU cluster performance |
| [HARDWARE-TIERING-RESEARCH.md](hardware/HARDWARE-TIERING-RESEARCH.md) | Hardware tier classification system |
| [MAC-MINI-AI-GUIDE-2026.md](hardware/MAC-MINI-AI-GUIDE-2026.md) | Running AI on Mac Mini (Apple Silicon) |
| [PI5-AI-GUIDE-2026.md](hardware/PI5-AI-GUIDE-2026.md) | Running AI on Raspberry Pi 5 |

---

### [`models/`](models/) — Models & Tool Calling (12 docs)

| Document | What It Covers |
|----------|---------------|
| [OSS-MODEL-LANDSCAPE-2026-02.md](models/OSS-MODEL-LANDSCAPE-2026-02.md) | Open-source model comparison (Feb 2026) |
| [M9-OSS-MODEL-LANDSCAPE-2026-02.md](models/M9-OSS-MODEL-LANDSCAPE-2026-02.md) | Milestone 9 model evaluation |
| [M9-LOCAL-VS-CLOUD-BENCHMARK.md](models/M9-LOCAL-VS-CLOUD-BENCHMARK.md) | Local vs cloud quality comparison |
| [TOOL-CALLING-SURVEY.md](models/TOOL-CALLING-SURVEY.md) | Tool calling comparison across model families |
| [tool-calling-qwen.md](models/tool-calling-qwen.md) | Qwen tool calling guide |
| [tool-calling-llama.md](models/tool-calling-llama.md) | Llama tool calling guide |
| [tool-calling-mistral.md](models/tool-calling-mistral.md) | Mistral tool calling guide |
| [tool-calling-deepseek.md](models/tool-calling-deepseek.md) | DeepSeek tool calling guide |
| [tool-calling-phi.md](models/tool-calling-phi.md) | Phi tool calling guide |
| [tool-calling-command-r.md](models/tool-calling-command-r.md) | Command-R tool calling guide |
| [vllm-tool-calling.md](models/vllm-tool-calling.md) | vLLM tool calling setup |
| [HOT-SWAP-BEST-PRACTICES.md](models/HOT-SWAP-BEST-PRACTICES.md) | Model hot-swapping patterns |

---

### [`voice/`](voice/) — Voice & Speech (11 docs)

| Document | What It Covers |
|----------|---------------|
| [M2-VOICE-LATENCY-OPTIMIZATION.md](voice/M2-VOICE-LATENCY-OPTIMIZATION.md) | Voice latency optimization (<2s round-trip) |
| [VOICE-LATENCY-OPTIMIZATION.md](voice/VOICE-LATENCY-OPTIMIZATION.md) | Voice latency deep dive |
| [voice-agent-latency-benchmarks.md](voice/voice-agent-latency-benchmarks.md) | Voice agent latency benchmarks |
| [voice-agent-scaling-architecture.md](voice/voice-agent-scaling-architecture.md) | Scaling voice agent infrastructure |
| [M8-VOICE-CAPACITY.md](voice/M8-VOICE-CAPACITY.md) | Voice system capacity planning |
| [M4-DETERMINISTIC-VOICE-RESEARCH.md](voice/M4-DETERMINISTIC-VOICE-RESEARCH.md) | Deterministic vs LLM voice handling |
| [M4-INTENT-TAXONOMY.md](voice/M4-INTENT-TAXONOMY.md) | Voice intent classification taxonomy |
| [DETERMINISTIC-CALL-FLOWS.md](voice/DETERMINISTIC-CALL-FLOWS.md) | FSM-based call flow patterns |
| [M9-STT-ENGINES.md](voice/M9-STT-ENGINES.md) | Speech-to-text engine comparison |
| [M9-TTS-ENGINES.md](voice/M9-TTS-ENGINES.md) | Text-to-speech engine comparison |
| [GPU-TTS-BENCHMARK.md](voice/GPU-TTS-BENCHMARK.md) | GPU vs CPU TTS performance benchmarks |

---

### [`security/`](security/) — Security & Privacy (3 docs)

| Document | What It Covers |
|----------|---------------|
| [M10-SECURITY-AUDIT-2026-02-11.md](security/M10-SECURITY-AUDIT-2026-02-11.md) | Ship-readiness audit (217 findings, 42 critical) |
| [M3-PII-DETECTION-LIBS.md](security/M3-PII-DETECTION-LIBS.md) | PII detection library comparison |

---

### [`architecture/`](architecture/) — DreamServer Architecture (8 docs)

| Document | What It Covers |
|----------|---------------|
| [DREAM-SERVER-SPEC.md](architecture/DREAM-SERVER-SPEC.md) | DreamServer product specification |
| [DREAM-SERVER-AUDIT-2026-02-13.md](architecture/DREAM-SERVER-AUDIT-2026-02-13.md) | Architecture audit and findings |
| [DREAM-SERVER-PUNCHLIST.md](architecture/DREAM-SERVER-PUNCHLIST.md) | Pre-launch punchlist |
| [LOCAL-AI-BEST-PRACTICES.md](architecture/LOCAL-AI-BEST-PRACTICES.md) | Production lessons from local AI deployments |
| [M11-UPDATE-SYSTEM-DESIGN.md](architecture/M11-UPDATE-SYSTEM-DESIGN.md) | Update system design |
| [M5-FIRST-RUN-WIZARD-DESIGN.md](architecture/M5-FIRST-RUN-WIZARD-DESIGN.md) | First-run experience design |
| [M5-STRANGER-TESTING-COMPLETE.md](architecture/M5-STRANGER-TESTING-COMPLETE.md) | Stranger testing results |
| [TOKEN-SPY-DREAM-INTEGRATION.md](architecture/TOKEN-SPY-DREAM-INTEGRATION.md) | Token Spy integration with DreamServer |

---

### [`market/`](market/) — Market & Competitive (4 docs)

| Document | What It Covers |
|----------|---------------|
| [EDGE-AI-MARKET-TRENDS-2025.md](market/EDGE-AI-MARKET-TRENDS-2025.md) | Edge AI market trends and analysis |
| [UNSOLVED-LOCAL-AI-PROBLEMS-2026.md](market/UNSOLVED-LOCAL-AI-PROBLEMS-2026.md) | Unsolved problems in local AI |
| [WINDOWS-LOCAL-AI-CHALLENGES-2026.md](market/WINDOWS-LOCAL-AI-CHALLENGES-2026.md) | Windows-specific local AI challenges |
| [competitor-analysis-2026-02-11.md](market/competitor-analysis-2026-02-11.md) | Competitive landscape analysis |

---

### [`livekit/`](livekit/) — LiveKit Integration (2 docs)

| Document | What It Covers |
|----------|---------------|
| [LIVEKIT-AGENTS-ARCHITECTURE.md](livekit/LIVEKIT-AGENTS-ARCHITECTURE.md) | LiveKit agents architecture |
| [LIVEKIT-SELF-HOSTING.md](livekit/LIVEKIT-SELF-HOSTING.md) | Self-hosting LiveKit |

---

## Quick Navigation

**Building an agentic coding tool?** → [`agent-systems/`](agent-systems/)

**Choosing hardware?** → [`hardware/HARDWARE-GUIDE.md`](hardware/HARDWARE-GUIDE.md)

**Setting up tool calling?** → [`models/TOOL-CALLING-SURVEY.md`](models/TOOL-CALLING-SURVEY.md) + per-model guides

**Building voice agents?** → [`voice/`](voice/) + [`../frameworks/voice-agent/`](../frameworks/voice-agent/)

**Security audit?** → [`security/M10-SECURITY-AUDIT-2026-02-11.md`](security/M10-SECURITY-AUDIT-2026-02-11.md)

**Understanding the market?** → [`market/`](market/)

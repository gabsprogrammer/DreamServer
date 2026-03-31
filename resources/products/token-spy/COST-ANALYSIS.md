# Token Spy — Cost Visibility Impact

What changed when we could actually see where the money was going.

---

## Before: Flying Blind

Running 3 AI agents 24/7 across two GPU servers with zero cost visibility. Per-turn costs were in the range of 5-6 cents, with some agents spiking to roughly 8 cents on heavy turns. We didn't know that at the time — there was nothing showing us.

The symptoms were indirect:
- API rate limit hits at unexpected times
- Monthly cloud bills that felt high but couldn't be attributed to specific agents or tasks
- No way to tell if a session was productive or if an agent was spinning in a loop
- Context windows silently growing, inflating per-turn costs with every message

The $79/day (Android-17) and $113/day (Todd) snapshots from early operation were discovered *after* Token Spy was running — before that, we had no per-agent breakdown at all.

## What Token Spy Revealed

Once per-turn token counts, cost breakdowns, and session sizes were visible on a live dashboard, the problems became obvious within hours:

**1. Model mismatch.** Agents were using frontier cloud models for tasks that a local 32B model handles fine — code generation, structured output, tool calling. Moving heavy-volume work to local Qwen via vLLM eliminated those costs entirely.

**2. Session bloat.** Without visibility into session size, context windows grew unchecked. Larger context = more input tokens per turn = higher cost per turn, compounding over time. Once we could see session sizes in real time, we added automated resets (Pattern 4) that kept sessions lean.

**3. Cache underutilization.** Anthropic's prompt caching can significantly reduce input costs for repetitive system prompts and tool definitions. Token Spy showed cache hit rates per agent, revealing which agents were benefiting from caching and which were missing it due to prompt variability.

**4. Waste loops.** Agents occasionally enter loops — calling the same tool repeatedly, generating similar responses, or retrying failed operations. Without per-turn visibility, these loops burned tokens silently for hours. Token Spy's session timeline made them immediately visible.

## After: Roughly 3-4x Reduction

Within a few days of having visibility, effective per-turn costs dropped by approximately 3-4x through a combination of:

- Routing high-volume work to local inference (zero marginal cost)
- Controlling session sizes to reduce input token inflation
- Matching models to actual task complexity (frontier for reasoning, local for execution)
- Catching and killing waste loops early

The exact reduction varies by workload and agent. The direction is consistent: you make very different decisions when you can see what's happening.

## Takeaway

The cost problem was never about expensive models. It was about not knowing which costs were productive and which were waste. Token Spy didn't reduce costs by being clever — it reduced costs by making the data visible so that humans could make obvious decisions they couldn't make before.

---

*See [PRODUCT-SCOPE.md](PRODUCT-SCOPE.md) for the full feature roadmap and [PHASE1-ARCHITECTURE.md](PHASE1-ARCHITECTURE.md) for the technical design.*

# vLLM Tool Calling Research Summary

## 1. Tool Calling Formats Supported

vLLM supports **OpenAI-compatible function calling** through its `/v1/chat/completions` API:

- **Named function calling** (default): Specify exact tool via `tool_choice={"type": "function", "function": {"name": "xyz"}}`
- **Automatic tool choice** (`tool_choice="auto"`): Model decides when to use tools
- **Required tool** (`tool_choice="required"`, vLLM >= 0.8.3): Forces at least one tool call
- **None** (`tool_choice="none"`): Disables tool calling even if tools provided

Supports standard OpenAI format with `tools`, `tool_choice`, and returns `tool_calls` array with `id`, `type`, `function.name`, and `function.arguments`.

## 2. Configuration

Enable tool calling at server startup with flags:

```bash
# Basic auto tool choice
vllm serve meta-llama/Llama-3.1-8B-Instruct \
  --enable-auto-tool-choice \
  --tool-call-parser llama3_json \
  --chat-template examples/tool_chat_template_llama3.1_json.jinja
```

**Key flags:**
- `--enable-auto-tool-choice` - Required for automatic tool selection
- `--tool-call-parser <parser>` - Parser for model's tool format
- `--chat-template <path>` - Custom template handling tool messages (optional for some models)
- `--tool-parser-plugin <path>` - Load custom parser plugins

**Note:** Named/required calling uses structured outputs backend - first call has latency overhead (FSM compilation).

## 3. Best Models for Tool Calling

| Model Family | Parser | Notes |
|--------------|--------|-------|
| **Llama 3.1/3.2/4** | `llama3_json` | Most stable; parallel calls supported in 3.2+ and 4.x |
| **Hermes 2 Pro / Hermes 3** | `hermes` | Excellent tool reliability |
| **Qwen 2.5** | `hermes` | Good tool support via Hermes-style templates |
| **Mistral 7B** | `mistral` | Use parallel template for better results |
| **IBM Granite 3.x/4.x** | `granite` | Solid for function calling |
| **OpenAI gpt-oss** | `openai` | Newer option |
| **DeepSeek-V3/V3.1** | `deepseek_v3` | Requires custom templates |

**Avoid:** Smaller models (<7B) struggle with tool calling consistency (e.g., Llama 3.2 1B/3B).

## 4. Limitations & Gotchas

- **Latency on first tool call**: Named/required tool choice compiles FSM on first use → several seconds delay (cached afterward)
- **Parallel tool calls**: Not supported for Llama 3.1 (works in 3.2+, 4.x, Hermes, Granite)
- **Chat templates matter**: Some models need custom templates for vLLM compatibility (especially Mistral, Llama 3.2)
- **Quality vs parseability**: vLLM guarantees *parseable* output via structured outputs, not necessarily *high-quality* tool calls
- **Tool call IDs**: Mistral requires 9-digit IDs (shorter than vLLM default) - templates provided handle this
- **Llama 3.2 small models**: Often fail to emit tool calls correctly
- **JSON format issues**: Models may serialize arrays as strings instead of proper JSON

## 5. Silent Compatibility Issues (Agent Frameworks)

When using vLLM as a backend for agent frameworks (OpenClaw, LangChain, custom loops), several parameters and response fields cause silent failures. No error, no warning — the agent just gets nothing back or the framework chokes on unexpected fields. These were discovered through production debugging and are handled by the [vllm-tool-proxy](../../tools/vllm-tool-proxy.py).

### Problem: Streaming + Tool Calls Don't Mix

If the client sends `"stream": true` with tools present, vLLM streams tokens incrementally. But tool calls embedded in content (common with models that output tool JSON as text rather than structured `tool_calls`) can't be extracted from a stream mid-flight. The framework receives partial JSON fragments and fails silently.

**Fix:** Force `"stream": false` when `tools` are present. Extract tool calls from the complete response, then optionally re-wrap as SSE if the client expects streaming.

### Problem: `stream_options` on Non-Streaming Requests

vLLM 0.14+ rejects requests that include `"stream_options"` when `"stream"` is `false`. The rejection is silent — the request either hangs or returns an empty response. Many frameworks send `stream_options` by default regardless of streaming mode.

**Fix:** Strip `"stream_options"` from the request body whenever `"stream"` is `false` or absent.

### Problem: Extra Response Fields Break Framework Parsers

vLLM returns fields that don't exist in the OpenAI spec. Frameworks that strictly validate response schemas fail silently when they encounter these. The problematic fields:

**Top-level:** `prompt_logprobs`, `prompt_token_ids`, `kv_transfer_params`, `service_tier`, `system_fingerprint`

**Per-choice:** `stop_reason`, `token_ids`

**Per-message:** `reasoning`, `reasoning_content`, `refusal`, `annotations`, `audio`, `function_call`

**Usage:** `prompt_tokens_details`

**Fix:** Strip all non-standard fields from the response before forwarding to the framework. Also ensure `tool_calls` is absent (not an empty list `[]`) when no tools were called — some frameworks treat `[]` as "tools were attempted and failed."

### Problem: Tool Calls Returned as Text Content

Some models (notably GPT-OSS-120B, some Qwen configurations) output tool calls as plain text in the `content` field rather than as structured `tool_calls`. The response looks normal to vLLM but the framework sees no tool calls and falls back to treating it as a text response.

Three formats observed:
1. `<tools>{"name": "func", "arguments": {...}}</tools>` — XML-wrapped JSON
2. `{"name": "func", "arguments": {...}}` — bare JSON as content
3. Multi-line JSON — multiple tool calls on separate lines

**Fix:** Post-process the response: if `tool_calls` is empty but `content` contains parseable tool JSON in any of these formats, extract it, build proper `tool_calls` structures, and set `finish_reason` to `"tool_calls"`.

### Implementation

All of these fixes are implemented in [`tools/vllm-tool-proxy.py`](../../tools/vllm-tool-proxy.py) — a Flask proxy that sits between the agent framework and vLLM. It also includes a loop breaker (`MAX_TOOL_CALLS = 20`) to abort runaway tool-calling loops.

---

## Quick Reference

```python
# Client example (OpenAI SDK)
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8000/v1", api_key="dummy")

response = client.chat.completions.create(
    model="model-name",
    messages=[{"role": "user", "content": "Weather in SF?"}],
    tools=[tools_def],
    tool_choice="auto"
)
```

**Template location:** `examples/tool_chat_template_*.jinja` in vLLM repo

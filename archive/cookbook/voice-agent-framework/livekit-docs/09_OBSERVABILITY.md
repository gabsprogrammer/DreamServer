# Data Hooks & Observability

**Source:** https://docs.livekit.io/deploy/observability/data/

## Overview

The LiveKit Agents SDK provides extensive access to session data for monitoring, debugging, and integration with external systems.

## Session Data Collection

### Conversation History via session.history

The `session.history` object contains the full conversation:

```python
# Get complete transcript
history = session.history
for msg in history.items:
    role = msg.role  # "user" or "assistant"
    text = msg.text_content
    created_at = msg.created_at
    print(f"[{created_at}] {role}: {text}")
```

### Session Reports

Use `ctx.make_session_report()` in the `on_session_end` callback:

```python
@server.rtc_session(on_session_end=handle_session_end)
async def my_agent(ctx):
    # Agent code
    pass

def handle_session_end(ctx, session):
    report = ctx.make_session_report()
    # Contains: job_id, conversation history, timestamps, events, recording metadata
    save_to_database(report)
```

### Real-Time Event Monitoring

Subscribe to events for live dashboards:

```python
@session.on("conversation_item_added")
def on_item(event):
    # Real-time transcript updates
    send_to_dashboard(event.item)

@session.on("user_input_transcribed")
def on_transcribed(event):
    # Real-time user speech
    log_user_speech(event.transcript, event.is_final)
```

## Metrics Collection

### Subscribing to Metrics

```python
@session.on("metrics_collected")
def on_metrics(event):
    for metric in event.metrics:
        # Forward to your monitoring system
        send_to_prometheus(metric)
```

### Available Metrics

**Voice Activity Detection (VAD):**
- `idle_time` - Time with no speech detected
- `inference_duration_total` - Total VAD processing time
- `inference_count` - Number of VAD inferences

**Speech-to-Text (STT):**
- `audio_duration` - Length of processed audio
- `processing_duration` - Time to transcribe
- `streaming_status` - Whether streaming STT is active

**End-of-Utterance (EOU):**
- `end_of_utterance_delay` - Time from speech end to turn completion
- `transcription_delay` - Time to get transcription
- `on_user_turn_completed_delay` - Handler execution time

**LLM:**
- `duration` - Total LLM call duration
- `completion_tokens` - Output tokens
- `prompt_tokens` - Input tokens
- `prompt_cached_tokens` - Cached prompt tokens
- `tokens_per_second` - Generation speed
- `ttft` (time-to-first-token) - Latency to first output token

**Text-to-Speech (TTS):**
- `audio_duration` - Length of generated audio
- `character_count` - Characters processed
- `duration` - Total TTS call duration
- `ttfb` (time-to-first-byte) - Latency to first audio

### Calculating Response Latency

Total user-perceived latency:
```
latency = eou.end_of_utterance_delay + llm.ttft + tts.ttfb
```

## Usage Tracking

### Aggregating Usage

```python
from livekit.agents import UsageCollector

collector = UsageCollector()

@session.on("metrics_collected")
def track_usage(event):
    collector.add_metrics(event.metrics)

# At session end
usage_summary = collector.get_summary()
# Includes: total tokens, audio minutes, character counts
```

## Audio & Video Recording

### Automatic Recording

Sessions are automatically recorded after noise cancellation processing.

### Custom Recording with Egress

```python
from livekit import api

# Start room composite recording
request = api.RoomCompositeEgressRequest(
    room_name=room_name,
    file=api.EncodedFileOutput(
        file_type=api.EncodedFileType.MP4,
        filepath="recordings/{room_name}/{time}.mp4",
    ),
)

lk_api = api.LiveKitAPI()
await lk_api.egress.start_room_composite_egress(request)
```

## OpenTelemetry Integration (Python)

Export traces to OpenTelemetry-compatible backends:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Set up tracer
provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="http://localhost:4317")
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# LiveKit will automatically export spans
```

## Best Practices

1. **Use session.history** for reliable transcript capture at session end
2. **Monitor metrics** to identify latency issues and optimize
3. **Implement session reports** for complete call records
4. **Set up real-time events** for live monitoring dashboards
5. **Track usage** for cost estimation and billing
6. **Use OpenTelemetry** for distributed tracing across your infrastructure

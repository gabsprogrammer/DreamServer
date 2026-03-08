# LiveKit Agents Events Reference

**Source:** https://docs.livekit.io/reference/other/events/

## Event Types

AgentSession emits several events to notify about state changes.

---

## user_input_transcribed

Emitted when user transcription becomes available.

**Properties:**
- `transcript` (str) - The transcribed text
- `is_final` (bool) - Whether this is a final transcription
- `language` (str) - Detected language
- `speaker_id` (str | None) - Speaker ID (with diarization)

**Python Example:**
```python
@session.on("user_input_transcribed")
def on_user_input_transcribed(event: UserInputTranscribedEvent):
    print(f"User said: {event.transcript}")
    print(f"Final: {event.is_final}")
```

---

## conversation_item_added

Fired when an item is committed to chat history (user or agent messages).

**Properties:**
- `item` (ChatMessage) - The message object with role, content, etc.

**Python Example:**
```python
@session.on("conversation_item_added")
def on_conversation_item(event: ConversationItemAddedEvent):
    item = event.item
    role = item.role  # "user" or "assistant"
    text = item.text_content  # The text content
    print(f"{role}: {text}")
```

**IMPORTANT NOTE:** There is a known issue where agent messages may arrive with empty content in certain conditions (e.g., during interruptions). For reliable transcript capture, use `session.history` after the session closes.

---

## speech_created

Triggered when agent generates speech.

**Properties:**
- `user_initiated` (bool) - Whether user action triggered this
- `source` (str) - "say", "generate_reply", or "tool_response"
- `speech_handle` - Reference to track speech playout

**Python Example:**
```python
@session.on("speech_created")
def on_speech(event: SpeechCreatedEvent):
    print(f"Speech created, source: {event.source}")
```

---

## agent_state_changed

Emitted when agent state transitions occur.

**Agent States:**
- `initializing` - Startup phase
- `listening` - Awaiting user input
- `thinking` - Processing input
- `speaking` - Actively speaking

**Python Example:**
```python
@session.on("agent_state_changed")
def on_agent_state(event: AgentStateChangedEvent):
    print(f"Agent state: {event.state}")
```

---

## user_state_changed

Reflects VAD-detected user state changes.

**User States:**
- `speaking` - Detected speech onset
- `listening` - Detected speech end
- `away` - No response for timeout period (default 15s)

**Python Example:**
```python
@session.on("user_state_changed")
def on_user_state(event: UserStateChangedEvent):
    print(f"User state: {event.state}")
```

---

## function_tools_executed

Emitted after all function tools execute for user input.

**Properties:**
- `function_calls` - List of executed calls
- `function_call_outputs` - Corresponding outputs

---

## metrics_collected

Signals new metrics availability.

**Includes:**
- STT metrics (audio_duration, processing_duration)
- LLM metrics (tokens, duration, ttft)
- TTS metrics (audio_duration, character_count, ttfb)
- VAD metrics (idle_time, inference_duration)
- EOU metrics (end_of_utterance_delay)

**Python Example:**
```python
@session.on("metrics_collected")
def on_metrics(event: MetricsCollectedEvent):
    for metric in event.metrics:
        print(f"Metric: {metric}")
```

---

## close

Fired when AgentSession terminates.

**Properties:**
- `error` (optional) - Error object if abnormal termination

**Python Example:**
```python
@session.on("close")
def on_close(event: CloseEvent):
    if event.error:
        print(f"Session closed with error: {event.error}")
    else:
        print("Session closed normally")
```

---

## agent_false_interruption

Emitted when user silence falsely triggers interruption detection.

**Properties:**
- `resumed` (bool) - Whether auto-resume occurred

---

## Error Event

Emitted during failures.

**Properties:**
- `model_config` - Current model configuration
- `error` - Error object with `recoverable` field
- `source` - Responsible component (LLM, STT, TTS, RealtimeModel)

**Recoverable field:**
- `True` - Informational; session continues
- `False` - Intervention required; use `.say()` to notify user

---

## Getting Transcript at Session End

**RECOMMENDED:** Instead of relying solely on events, get the complete transcript from `session.history` when the session closes:

```python
@ctx.room.on("participant_disconnected")
def on_disconnect(participant):
    # Get complete transcript from session.history
    history = session.history
    for msg in history.items:
        role = msg.role
        text = msg.text_content or ""
        print(f"{role}: {text}")
```

The `session.history` property returns a `ChatContext` containing all conversation turns and is the most reliable way to get the complete transcript.

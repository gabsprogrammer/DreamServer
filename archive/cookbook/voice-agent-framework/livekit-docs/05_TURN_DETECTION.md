# Turn Detection and Interruptions

**Source:** https://docs.livekit.io/agents/build/turns/

## Overview

Turn detection is the process of determining when a user begins or ends their "turn" in a conversation. This lets the agent know when to start listening and when to respond.

Most turn detection techniques rely on voice activity detection (VAD) to detect periods of silence in user input. The agent applies heuristics to the VAD data to perform phrase endpointing, which determines the end of a sentence or thought.

## Turn Detection Modes

### 1. Turn Detector Model (Recommended)

A custom, open-weights model for context-aware turn detection on top of VAD. This is the recommended approach for best user experience.

```python
from livekit.plugins.turn_detector.multilingual import MultilingualModel
from livekit.plugins import silero

session = AgentSession(
    turn_detection=MultilingualModel(),
    vad=silero.VAD.load(),
    # ... other config
)
```

**Why use it:** Traditional VAD models can interrupt users during natural pauses (e.g., "I need to think about that for a moment..."). The turn detector model understands language context and waits appropriately.

### 2. Realtime Models

Built-in turn detection from providers like OpenAI Realtime API and Gemini Live API. Cost-effective since it doesn't require separate STT.

```python
from livekit.plugins import openai

session = AgentSession(
    llm=openai.realtime.RealtimeModel(voice="coral"),
    # Turn detection is handled by the realtime model
)
```

### 3. VAD Only

Detect end of turn from speech and silence data alone. Works across any spoken language without language-specific models.

```python
session = AgentSession(
    turn_detection="vad",
    vad=silero.VAD.load(),
)
```

### 4. STT Endpointing

Use phrase endpoints returned in realtime STT data. AssemblyAI's semantic endpointing is particularly effective.

```python
session = AgentSession(
    turn_detection="stt",
    stt="assemblyai/universal-streaming:en",
    vad=silero.VAD.load(),  # Still recommended for interruption responsiveness
)
```

### 5. Manual Control

Disable automatic detection and control turns explicitly.

```python
session = AgentSession(
    turn_detection="manual",
)

# Then control manually:
session.interrupt()           # Stop agent speech
session.clear_user_turn()     # Discard pending input
session.commit_user_turn()    # Process accumulated input
session.input.set_audio_enabled(False)  # Stop listening
```

## Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `allow_interruptions` | True | Permit user interruption during agent speech |
| `discard_audio_if_uninterruptible` | True | Drop buffered audio during uninterruptible agent speech |
| `min_interruption_duration` | 0.5s | Minimum detected speech before triggering interruption |
| `min_interruption_words` | 0 | Minimum words for interruption (STT-based only) |
| `min_endpointing_delay` | 0.5s | Minimum delay before considering turn complete |
| `max_endpointing_delay` | 3.0s | Maximum wait for continued user speech |
| `false_interruption_timeout` | 2.0s | Delay before detecting false positive |
| `resume_false_interruption` | True | Resume agent speech after false detection |

## Interruption Handling

The framework automatically pauses agent speech when detecting user input.

### Automatic Interruption
```python
# By default, users can interrupt anytime
session = AgentSession(allow_interruptions=True)
```

### Preventing Interruption for Specific Speech
```python
# Don't allow interruption for this specific utterance
await session.say("Please listen carefully...", allow_interruptions=False)

# Or for generated replies
await session.generate_reply(
    instructions="Give important safety information.",
    allow_interruptions=False
)
```

### Programmatic Interruption
```python
# Always works, regardless of allow_interruptions setting
session.interrupt()
```

## False Interruption Handling

When VAD detects speech but STT produces no words, it's likely a false positive (cough, noise, etc.).

```python
session = AgentSession(
    false_interruption_timeout=2.0,  # Wait 2s before declaring false positive
    resume_false_interruption=True,   # Auto-resume from where agent left off
)

# Listen for false interruption events
@session.on("agent_false_interruption")
def on_false_interruption(event):
    if event.resumed:
        print("Resumed after false interruption")
```

## State Events

Monitor conversation flow:

```python
@session.on("user_state_changed")
def on_user_state(event):
    # States: speaking, listening, away
    print(f"User state: {event.state}")

@session.on("agent_state_changed")
def on_agent_state(event):
    # States: initializing, idle, listening, thinking, speaking
    print(f"Agent state: {event.state}")
```

## Best Practices

1. **Always use VAD** even with STT endpointing for better interruption responsiveness
2. **Use the turn detector model** for best user experience in English/multilingual apps
3. **Set appropriate timeouts** based on your use case (shorter for fast-paced, longer for thoughtful conversations)
4. **Handle false interruptions** gracefully to avoid jarring user experience
5. **Use noise cancellation** for better VAD accuracy

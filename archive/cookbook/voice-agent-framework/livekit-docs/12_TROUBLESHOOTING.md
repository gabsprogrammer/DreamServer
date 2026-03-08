# Troubleshooting Guide

## Common Issues & Solutions

---

## Transcript Not Being Captured

### Symptoms
- `call_data.transcript_lines` is empty after call ends
- Events fire but content is missing

### Solution
**Use `session.history` instead of event handlers for final transcript:**

```python
# CORRECT - Get transcript from session.history after disconnect
@ctx.room.on("participant_disconnected")
def on_disconnect(participant):
    history = session.history
    for msg in history.items:
        role = msg.role
        text = msg.text_content or ""
        if text.strip():
            call_data.add_transcript_line(
                "Caller" if role == "user" else "Grace",
                text.strip()
            )
```

### Why This Happens
- Event handlers like `conversation_item_added` may receive empty content for agent messages
- This is a known issue in the LiveKit SDK (GitHub issue #2216)
- `session.history` is the authoritative source for the complete conversation

---

## Agent Not Responding After Start

### Symptoms
- Agent connects but doesn't speak
- No greeting is played

### Solution
**Call `generate_reply()` AFTER `session.start()`:**

```python
# CORRECT
await session.start(room=ctx.room, agent=MyAgent())
await session.generate_reply(instructions="Greet the user.")

# WRONG - Won't work
await session.generate_reply(instructions="Greet the user.")
await session.start(room=ctx.room, agent=MyAgent())
```

---

## Turn Detection Not Working

### Symptoms
- Agent interrupts user mid-sentence
- Agent waits too long to respond

### Solution
**Use the Turn Detector Model with VAD:**

```python
from livekit.plugins.turn_detector.multilingual import MultilingualModel
from livekit.plugins import silero

session = AgentSession(
    turn_detection=MultilingualModel(),
    vad=silero.VAD.load(),
    min_endpointing_delay=0.5,  # Adjust as needed
    max_endpointing_delay=3.0,
)
```

---

## Events Not Firing

### Symptoms
- `@session.on("event")` handlers never called
- Debug logs not written

### Solution
**Register event handlers AFTER `session.start()`:**

```python
await session.start(room=ctx.room, agent=MyAgent())

# Register handlers AFTER start
@session.on("user_input_transcribed")
def on_user_speech(event):
    # This will now work
    pass
```

---

## False Interruptions

### Symptoms
- Agent stops speaking when no user speech occurred
- Noise causes agent to pause

### Solution
**Configure false interruption handling:**

```python
session = AgentSession(
    false_interruption_timeout=2.0,  # Wait 2s before declaring false positive
    resume_false_interruption=True,  # Auto-resume
    min_interruption_duration=0.5,   # Require 0.5s of speech
)
```

**Add noise cancellation:**

```python
room_options=room_io.RoomOptions(
    audio_input=room_io.AudioInputOptions(
        noise_cancellation=noise_cancellation.BVC(),
    ),
)
```

---

## Session Closes Unexpectedly

### Symptoms
- Session ends without user hanging up
- Random disconnections

### Solution
**Check user_away_timeout setting:**

```python
session = AgentSession(
    user_away_timeout=30.0,  # Increase from default 15s
    # Or disable: user_away_timeout=None
)
```

---

## Multiple Agents Running

### Symptoms
- Duplicate responses
- Race conditions

### Solution
**Kill extra processes:**

```bash
pkill -f "python.*hvac_agent"
# Then restart
python hvac_agent.py dev
```

---

## Webhook/API Not Receiving Data

### Symptoms
- Tickets not created
- API calls failing

### Solution
**Check URL configuration:**

```python
# Verify the URL is accessible from the agent
N8N_URL = os.getenv("N8N_URL", "http://localhost:5678/webhook/ticket")

# Test manually
curl -X POST http://localhost:5678/webhook/ticket   -H "Content-Type: application/json"   -d '{"test": "data"}'
```

---

## Audio Quality Issues

### Symptoms
- Choppy audio
- Echo
- Background noise

### Solution
**Use appropriate noise cancellation:**

```python
from livekit.plugins import noise_cancellation
from livekit import rtc

room_options=room_io.RoomOptions(
    audio_input=room_io.AudioInputOptions(
        noise_cancellation=lambda params:
            # Use telephony-optimized for phone calls
            noise_cancellation.BVCTelephony()
            if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
            else noise_cancellation.BVC()
    ),
)
```

---

## Debug Logging

Add comprehensive logging to trace issues:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

# Or log to file
with open("/tmp/debug.log", "a") as f:
    f.write(f"[{datetime.now()}] Event: {event}\n")
```

---

## Useful Commands

```bash
# Check agent processes
ps aux | grep hvac_agent

# View agent logs
tail -f /tmp/hvac_agent.log

# Check debug log
cat /tmp/hvac_debug.log

# Test webhook manually
curl -X POST http://localhost:5678/webhook/ticket   -H "Content-Type: application/json"   -d '{"category": "test", "summary": "Test ticket"}'

# Restart agent
pkill -f "python.*hvac_agent" && python hvac_agent.py dev
```

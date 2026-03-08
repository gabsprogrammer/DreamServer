# Text and Transcriptions

**Source:** https://docs.livekit.io/agents/build/text/

## Overview

LiveKit Agents supports real-time text input/output alongside audio processing. The system uses text stream topics to handle transcriptions and messages between agents and frontends.

## Transcription Output

### Default Behavior

Transcriptions automatically publish to frontends in real-time using the `lk.transcription` text stream topic.

```python
# Transcription output is enabled by default
session = AgentSession(...)

await session.start(
    room=ctx.room,
    agent=MyAgent(),
    room_options=room_io.RoomOptions(
        text_output=True,  # Default
    ),
)
```

### Disabling Transcription Output

```python
room_options=room_io.RoomOptions(
    text_output=False,
)
```

### Synchronized Transcription

When enabled, agent speech synchronizes with transcriptions, displaying text word-by-word during speech:

```python
room_options=room_io.RoomOptions(
    text_output=room_io.TextOutputOptions(
        sync_transcription=True,  # Default
    ),
)
```

If interrupted, transcriptions truncate to match spoken output.

### TTS-Aligned Transcriptions (Python Only)

For improved word-level synchronization with Cartesia or ElevenLabs:

```python
session = AgentSession(
    use_tts_aligned_transcript=True,
)
```

Access timing data via the `transcription_node`:

```python
class MyAgent(Agent):
    def transcription_node(self, text, model_settings):
        async for chunk in text:
            if isinstance(chunk, TimedString):
                # Access timing: chunk.start_time, chunk.end_time
                print(f"Word: {chunk} ({chunk.start_time}s - {chunk.end_time}s)")
            yield chunk
```

## Text Input

### Default Text Input

Agents monitor the `lk.chat` text stream topic for incoming messages:

```python
# Text input is enabled by default
room_options=room_io.RoomOptions(
    text_input=True,
)
```

### Frontend Sending Text

```javascript
// From frontend
await room.localParticipant.sendText(text, { topic: lk.chat });
```

### Programmatic Text Input

```python
# Inject text as if user said it
await session.generate_reply(user_input="I need help with my order")
```

### Custom Text Handler

Replace default behavior with a callback:

```python
def custom_text_handler(session: AgentSession, event: room_io.TextInputEvent):
    message = event.text
    
    # Handle commands
    if message.startswith("/"):
        handle_command(message)
        return
    
    # Filter or transform
    if is_spam(message):
        return
    
    # Generate response
    session.interrupt()
    session.generate_reply(user_input=message)

room_options=room_io.RoomOptions(
    text_input=custom_text_handler,
)
```

## Text-Only Sessions

Disable audio entirely for text-only conversations:

```python
room_options=room_io.RoomOptions(
    audio_input=False,
    audio_output=False,
    text_input=True,
    text_output=True,
)
```

## Hybrid Sessions

Toggle audio dynamically:

```python
# Start with audio
session.input.set_audio_enabled(True)
session.output.set_audio_enabled(True)

# Switch to text-only
session.input.set_audio_enabled(False)
session.output.set_audio_enabled(False)
```

## Getting Complete Transcript

### Via session.history (Recommended)

The most reliable way to get the complete transcript:

```python
# After call ends
history = session.history
for msg in history.items:
    role = msg.role  # "user" or "assistant"
    text = msg.text_content
    print(f"{role}: {text}")
```

### Via Events (Real-time)

```python
@session.on("user_input_transcribed")
def on_user_transcribed(event):
    if event.is_final:
        print(f"User: {event.transcript}")

@session.on("conversation_item_added")
def on_item_added(event):
    item = event.item
    role = item.role
    text = item.text_content
    print(f"{role}: {text}")
```

**Note:** The `conversation_item_added` event may have empty content for agent messages in certain conditions. Always fall back to `session.history` for complete transcripts.

## Frontend Reception

```javascript
// React hook
import { useTranscriptions } from @livekit/components-react;

function TranscriptionDisplay() {
    const transcriptions = useTranscriptions();
    return (
        <div>
            {transcriptions.map((t, i) => (
                <p key={i}>{t.text}</p>
            ))}
        </div>
    );
}
```

Or manually with `registerTextStreamHandler()`:

```javascript
room.registerTextStreamHandler(lk.transcription, (reader, participantInfo) => {
    reader.onProgress(segment => {
        console.log(Transcript segment:, segment.text);
    });
});
```

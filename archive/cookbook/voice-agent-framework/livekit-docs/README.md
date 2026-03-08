# LiveKit Agents Documentation Library

**Last Updated:** January 31, 2026  
**SDK Version:** 1.3.x  
**Source:** https://docs.livekit.io/agents/

## Contents

| File | Description |
|------|-------------|
| [01_INTRODUCTION.md](01_INTRODUCTION.md) | Framework overview, architecture, capabilities |
| [02_AGENT_SESSION.md](02_AGENT_SESSION.md) | AgentSession class - lifecycle, configuration, methods |
| [03_EVENTS.md](03_EVENTS.md) | All events reference - user_input_transcribed, conversation_item_added, etc. |
| [04_AGENT_CLASS.md](04_AGENT_CLASS.md) | Agent class - building agents, on_enter, tools |
| [05_TURN_DETECTION.md](05_TURN_DETECTION.md) | Turn detection modes, VAD, interruption handling |
| [06_FUNCTION_TOOLS.md](06_FUNCTION_TOOLS.md) | Function tools - @function_tool decorator, RunContext |
| [07_TEXT_TRANSCRIPTIONS.md](07_TEXT_TRANSCRIPTIONS.md) | Text I/O, transcript capture, session.history |
| [08_TELEPHONY.md](08_TELEPHONY.md) | SIP integration, inbound/outbound calls |
| [09_OBSERVABILITY.md](09_OBSERVABILITY.md) | Metrics, logging, OpenTelemetry integration |
| [10_QUICKSTART.md](10_QUICKSTART.md) | Complete quickstart guide with code examples |

## Quick Reference

### Creating a Basic Agent

```python
from livekit.agents import AgentServer, AgentSession, Agent, room_io
from livekit.plugins import silero, noise_cancellation
from livekit.plugins.turn_detector.multilingual import MultilingualModel

class MyAgent(Agent):
    def __init__(self):
        super().__init__(
            instructions="You are a helpful assistant."
        )
    
    async def on_enter(self):
        await self.session.generate_reply(
            instructions="Greet the user."
        )

server = AgentServer()

@server.rtc_session()
async def entrypoint(ctx):
    session = AgentSession(
        stt="assemblyai/universal-streaming:en",
        llm="openai/gpt-4.1-mini",
        tts="cartesia/sonic-3:voice-id",
        vad=silero.VAD.load(),
        turn_detection=MultilingualModel(),
    )
    
    await session.start(
        room=ctx.room,
        agent=MyAgent(),
        room_options=room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=noise_cancellation.BVC(),
            ),
        ),
    )

if __name__ == "__main__":
    from livekit import agents
    agents.cli.run_app(server)
```

### Getting Transcript (IMPORTANT)

The most reliable way to get the complete transcript:

```python
# After session ends - use session.history
history = session.history
for msg in history.items:
    role = msg.role  # "user" or "assistant"
    text = msg.text_content
    print(f"{role}: {text}")
```

### Key Events

```python
@session.on("user_input_transcribed")
def on_user_speech(event):
    print(f"User: {event.transcript}")

@session.on("conversation_item_added")
def on_item(event):
    print(f"{event.item.role}: {event.item.text_content}")

@session.on("close")
def on_close(event):
    # Session ended - capture final transcript
    transcript = session.history
```

### Turn Detection Options

```python
# Option 1: Turn detector model (recommended)
turn_detection=MultilingualModel()

# Option 2: VAD only
turn_detection="vad"

# Option 3: STT endpointing
turn_detection="stt"

# Option 4: Manual control
turn_detection="manual"
```

## Online Documentation

- Main Docs: https://docs.livekit.io/agents/
- Python API Reference: https://docs.livekit.io/reference/python/v1/livekit/agents/
- GitHub: https://github.com/livekit/agents

## Notes for HVAC Grace Project

1. **Transcript Capture**: Use `session.history` after disconnect - event handlers may miss content
2. **Turn Detection**: Using `MultilingualModel()` with Silero VAD for best results
3. **Noise Cancellation**: Use `BVCTelephony()` for SIP/phone calls
4. **Agent Handoffs**: Use `session.update_agent(new_agent)` for department transfers

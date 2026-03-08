# Voice AI Quickstart

**Source:** https://docs.livekit.io/agents/start/voice-ai-quickstart/

## Overview

Build a functioning voice assistant in under 10 minutes using LiveKit Agents.

## Requirements

- **Python**: Version 3.10-3.13 with `uv` package manager
- **LiveKit Cloud account**: Free at https://cloud.livekit.io/

## Project Setup

### 1. Initialize Project

```bash
uv init livekit-voice-agent --bare
cd livekit-voice-agent
```

### 2. Install Dependencies

**For STT-LLM-TTS Pipeline:**
```bash
uv add "livekit-agents[silero,turn-detector]~=1.3" \
  "livekit-plugins-noise-cancellation~=0.2" \
  "python-dotenv"
```

**For OpenAI Realtime Model:**
```bash
uv add "livekit-agents[openai]~=1.3" \
  "livekit-plugins-noise-cancellation~=0.2" \
  "python-dotenv"
```

### 3. Configure Environment

Run `lk app env -w` to generate `.env.local`:

```bash
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
LIVEKIT_URL=wss://your-project.livekit.cloud
OPENAI_API_KEY=your_openai_key
```

## Agent Implementation

### STT-LLM-TTS Pipeline

```python
# agent.py
from dotenv import load_dotenv
from livekit import agents, rtc
from livekit.agents import AgentServer, AgentSession, Agent, room_io
from livekit.plugins import noise_cancellation, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

load_dotenv(".env.local")

class Assistant(Agent):
    def __init__(self):
        super().__init__(
            instructions="""You are a helpful voice AI assistant.
            You eagerly assist users with their questions."""
        )

server = AgentServer()

@server.rtc_session()
async def my_agent(ctx: agents.JobContext):
    session = AgentSession(
        stt="assemblyai/universal-streaming:en",
        llm="openai/gpt-4.1-mini",
        tts="cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc",
        vad=silero.VAD.load(),
        turn_detection=MultilingualModel(),
    )

    await session.start(
        room=ctx.room,
        agent=Assistant(),
        room_options=room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=lambda params:
                    noise_cancellation.BVCTelephony()
                    if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
                    else noise_cancellation.BVC()
            ),
        ),
    )

    await session.generate_reply(
        instructions="Greet the user and offer your assistance."
    )

if __name__ == "__main__":
    agents.cli.run_app(server)
```

### OpenAI Realtime Model

```python
from livekit.plugins import openai, noise_cancellation

session = AgentSession(
    llm=openai.realtime.RealtimeModel(voice="coral")
)

await session.start(
    room=ctx.room,
    agent=Assistant(),
    room_options=room_io.RoomOptions(
        audio_input=room_io.AudioInputOptions(
            noise_cancellation=lambda params:
                noise_cancellation.BVCTelephony()
                if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
                else noise_cancellation.BVC()
        ),
    ),
)
```

## Running Your Agent

### Console Mode (Local Testing)

```bash
uv run agent.py console
```

Enables terminal-based testing with direct voice interaction.

### Development Mode

```bash
uv run agent.py dev
```

Connects to LiveKit Cloud; access via Agents Playground.

### Production Mode

```bash
uv run agent.py start
```

## Deployment

```bash
lk agent create
```

This generates `Dockerfile`, `.dockerignore`, and `livekit.toml`, then deploys to LiveKit Cloud.

## Next Steps

- **Custom Frontend**: Build web/mobile apps via Agent Frontends docs
- **Telephony**: Integrate SIP for phone calls
- **Testing**: Implement behavioral validation
- **Advanced Features**: Multimodality, workflows, external data

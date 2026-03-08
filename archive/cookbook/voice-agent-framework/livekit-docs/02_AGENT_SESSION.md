# AgentSession Documentation

**Source:** https://docs.livekit.io/agents/logic/sessions/

## Overview

AgentSession serves as the primary orchestrator for voice AI applications. It manages:
- User input collection
- Voice pipeline orchestration
- LLM invocation
- Output delivery
- Event emission for observability and control

## Core Lifecycle Phases

The session progresses through four distinct states:

1. **Initializing** - Setup phase with no media processing
2. **Starting** - I/O connections established, agent transitions to "listening"
3. **Running** - Active user input processing and response generation
4. **Closing** - Graceful shutdown with pending speech drainage and transcript commitment

## Constructor Parameters

```python
AgentSession(
    # Turn Detection
    turn_detection: TurnDetectionMode = MultilingualModel(),  # or "vad", "stt", "manual"
    
    # AI Components
    stt: STT | str = "assemblyai/universal-streaming:en",
    vad: VAD = silero.VAD.load(),
    llm: LLM | str = "openai/gpt-4.1-mini",
    tts: TTS | str = "cartesia/sonic-3:...",
    
    # Tools
    tools: list[Tool | Toolset] = [],
    mcp_servers: list[MCPServer] = [],
    max_tool_steps: int = 3,
    
    # User Interaction
    allow_interruptions: bool = True,
    discard_audio_if_uninterruptible: bool = True,
    min_interruption_duration: float = 0.5,
    min_interruption_words: int = 0,
    
    # Timing
    min_endpointing_delay: float = 0.5,
    max_endpointing_delay: float = 3.0,
    user_away_timeout: float = 15.0,
    false_interruption_timeout: float = 2.0,
    resume_false_interruption: bool = True,
    min_consecutive_speech_delay: float = 0.0,
    
    # Advanced
    preemptive_generation: bool = False,
    use_tts_aligned_transcript: bool = False,
    tts_text_transforms: Sequence[TextTransforms] = [],
    ivr_detection: bool = False,
    userdata: Any = None,
)
```

## Key Properties

```python
session.history          # Complete conversation history (ChatContext)
session.current_speech   # Active speech handle
session.user_state       # User activity state (speaking/listening/away)
session.agent_state      # Agent activity state (initializing/listening/thinking/speaking)
session.current_agent    # Active agent instance
session.tools            # Available tools
session.room_io          # Room I/O controller
session.input            # Input configuration
session.output           # Output configuration
session.userdata         # Custom session data
```

## Key Methods

### Starting a Session

```python
await session.start(
    room=ctx.room,
    agent=MyAgent(),
    room_options=room_io.RoomOptions(
        audio_input=room_io.AudioInputOptions(
            noise_cancellation=noise_cancellation.BVC()
        ),
    ),
)
```

### Generating Responses

```python
# Generate a reply with specific instructions
await session.generate_reply(
    instructions="Greet the user and offer your assistance."
)

# Speak text directly
await session.say("Hello\! How can I help you today?")
```

### Turn Control

```python
session.interrupt()           # Stop agent speech
session.clear_user_turn()     # Discard pending input
session.commit_user_turn()    # Process input
session.input.set_audio_enabled(False)  # Toggle listening
```

### Session Lifecycle

```python
await session.drain()         # Wait for activity completion
session.shutdown(drain=True)  # Graceful termination
```

## RoomIO Integration

RoomIO provides a bridge between the agent session and the LiveKit room, enabling automatic media track management and participant subscription handling.

### Room Options

```python
room_io.RoomOptions(
    # Audio Input
    audio_input=room_io.AudioInputOptions(
        noise_cancellation=noise_cancellation.BVC(),
    ),
    
    # Text Input
    text_input=True,  # or custom callback
    
    # Audio Output
    audio_output=True,
    
    # Text Output
    text_output=room_io.TextOutputOptions(
        sync_transcription=True,
    ),
    
    # Cleanup
    auto_close_on_participant_left=True,
)
```

## Code Example

```python
from livekit.agents import AgentServer, AgentSession, Agent, room_io
from livekit.plugins import silero, noise_cancellation
from livekit.plugins.turn_detector.multilingual import MultilingualModel

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

    await session.generate_reply(
        instructions="Greet the user."
    )
```

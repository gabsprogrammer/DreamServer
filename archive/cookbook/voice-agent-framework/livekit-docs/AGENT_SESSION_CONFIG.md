# AgentSession Configuration (SDK 1.3.x)

Source: https://docs.livekit.io/agents/logic/sessions/

## Turn Detection & Timing Parameters

These are set on the Agent class, not AgentSession:
- min_endpointing_delay: float - Minimum time to wait before detecting end of speech
- max_endpointing_delay: float - Maximum time to wait for end of speech  
- turn_detection: TurnDetection model (e.g., MultilingualModel())

## AgentSession Constructor Options

### Timing
- user_away_timeout: Time in seconds of silence before user state = away (default: 15.0)
- min_consecutive_speech_delay: Min delay between agent utterances (default: 0.0)

### AI Models  
- stt: Speech-to-text model
- llm: Language model
- tts: Text-to-speech model  
- vad: Voice Activity Detection model

### Tools
- tools: List of FunctionTool objects
- max_tool_steps: Max consecutive tool calls per LLM turn (default: 3)
- mcp_servers: Model Context Protocol servers

### Text Processing
- tts_text_transforms: Filters for markdown/emoji (applied by default)
- use_tts_aligned_transcript: Boolean

### Performance
- preemptive_generation: Begin LLM/TTS requests before end-of-turn detected

## Agent Class Configuration

The Agent class accepts turn detection parameters in its constructor:
```python
class MyAgent(Agent):
    def __init__(self):
        super().__init__(
            instructions="...",
            min_endpointing_delay=0.8,  # Wait 0.8s before end-of-turn
        )
```

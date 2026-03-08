# OpenAI Integration

**Source:** https://docs.livekit.io/agents/openai/

## Overview

LiveKit Agents integrates OpenAI's AI models and services for building realtime voice AI applications.

## Supported OpenAI Models

### LLM Models
- GPT-4.1, GPT-5, GPT-4o, o1-mini
- Available through LiveKit Inference with automatic billing

### Speech Recognition
- `whisper-1` - Industry standard
- `gpt-4o-transcribe` - Advanced transcription

### Text-to-Speech
- `tts-1` - Standard TTS
- `gpt-4o-mini-tts` - Lifelike speech generation

### Realtime API
Speech-to-speech model supporting live video input and bidirectional communication.

## STT-LLM-TTS Pipeline

```python
from livekit.agents import AgentSession

session = AgentSession(
    stt="openai/whisper-1",  # or "openai/gpt-4o-transcribe"
    llm="openai/gpt-4.1-mini",
    tts="openai/tts-1",  # or "openai/gpt-4o-mini-tts"
)
```

## Realtime API Integration

```python
from livekit.plugins import openai

session = AgentSession(
    llm=openai.realtime.RealtimeModel(
        voice="coral",  # Options: alloy, ash, ballad, coral, echo, sage, shimmer, verse
    )
)
```

### Available Voices
- `alloy` - Neutral
- `ash` - Soft
- `ballad` - Warm
- `coral` - Expressive (default)
- `echo` - Clear
- `sage` - Authoritative
- `shimmer` - Bright
- `verse` - Dynamic

## Benefits of LiveKit + OpenAI

LiveKit provides:
- WebRTC audio stream conversion to/from Realtime API
- Automatic interruption handling
- Noise cancellation with one line of code
- SIP-based telephony for phone calls
- Automatic transcription synchronization

## Azure OpenAI Support

```python
from livekit.plugins import openai

llm = openai.LLM(
    base_url="https://your-resource.openai.azure.com/",
    api_key="your-azure-key",
    model="your-deployment-name",
)
```

## Model Strings for LiveKit Inference

| Type | Model String |
|------|--------------|
| STT | `"openai/whisper-1"` |
| STT | `"openai/gpt-4o-transcribe"` |
| LLM | `"openai/gpt-4.1-mini"` |
| LLM | `"openai/gpt-4o"` |
| TTS | `"openai/tts-1"` |
| TTS | `"openai/gpt-4o-mini-tts"` |

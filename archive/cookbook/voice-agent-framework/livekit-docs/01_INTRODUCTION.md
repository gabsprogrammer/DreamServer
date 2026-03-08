# LiveKit Agents Framework - Introduction

**Source:** https://docs.livekit.io/agents/

## Overview

LiveKit provides a realtime framework for voice, video, and physical AI agents. The framework enables developers to add Python or Node.js programs to LiveKit rooms as full participants.

## Core Architecture

### How It Works

Agents operate as stateful bridges connecting AI models with users. The system uses WebRTC to ensure smooth communication between agents and users, even over unstable connections. Agent servers register with LiveKit, receive dispatch requests, and spawn job subprocesses that join rooms.

The framework handles:
- Streaming audio through an STT-LLM-TTS pipeline
- Reliable turn detection
- Handling interruptions
- LLM orchestration

## Key Capabilities

**Multimodality**: Agents process speech, text, and vision inputs, enabling richer, more natural interactions where they understand context from different sources.

**Production Ready**: Features include built-in agent server orchestration, load balancing, and Kubernetes compatibility.

**Tool Integration**: Define tools that are compatible with any LLM, and even forward tool calls to your frontend.

**Open Source**: The ecosystem operates under the Apache 2.0 license.

## Use Cases

- Multimodal assistants for talk, text, and screen sharing
- Telehealth consultations with AI integration
- Call center AI for inbound/outbound support
- Real-time translation
- AI-powered NPCs
- Cloud-based robotics brains

## Getting Started

Key resources include:
- **Voice AI quickstart**: Build and deploy a simple voice assistant with Python or Node.js in less than 10 minutes
- **Agent Builder**: Prototype agents directly in browsers without coding
- **Deeplearning.ai course**: Free production-focused training

## Integration Ecosystem

The framework supports plugins for most major AI providers including:
- OpenAI, Google, Azure, AWS, xAI, Groq, and Cerebras for LLMs
- Various STT providers (Deepgram, AssemblyAI, Whisper)
- Various TTS providers (Cartesia, ElevenLabs, OpenAI)
- Realtime APIs (OpenAI Realtime, Gemini Live)

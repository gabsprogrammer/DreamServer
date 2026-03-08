# Agent Class Documentation

**Source:** https://docs.livekit.io/reference/python/v1/livekit/agents/voice/index.html

## Overview

The Agent class is the main voice agent class for building conversational AI systems. It defines the behavior, instructions, and capabilities of your voice AI.

## Constructor Parameters

```python
class MyAgent(Agent):
    def __init__(self):
        super().__init__(
            # Core
            instructions="You are a helpful voice AI assistant.",
            id="my-agent-id",
            
            # Chat Context
            chat_ctx=None,  # Optional initial context
            
            # Tools
            tools=[],  # List of function tools
            mcp_servers=[],  # MCP server connections
            
            # AI Components (override session defaults)
            stt=None,
            llm=None,
            tts=None,
            vad=None,
            turn_detection=None,
            
            # Behavior
            allow_interruptions=True,
            min_endpointing_delay=0.5,
            max_endpointing_delay=3.0,
            min_consecutive_speech_delay=0.0,
            use_tts_aligned_transcript=False,
        )
```

## Key Properties

```python
agent.id                  # Agent identifier
agent.label               # Display label (mirrors id)
agent.instructions        # Behavioral instructions
agent.tools               # Available tools
agent.chat_ctx            # Read-only conversation history
agent.session             # Associated AgentSession
agent.stt                 # STT component
agent.llm                 # LLM component
agent.tts                 # TTS component
agent.vad                 # VAD component
agent.turn_detection      # Turn detection mode
agent.mcp_servers         # MCP servers
```

## Key Methods

### Lifecycle Methods

```python
async def on_enter(self):
    """Called when agent becomes active (after handoff or initial start)."""
    # Generate initial greeting
    await self.session.generate_reply(
        instructions="Greet the user warmly."
    )

async def on_exit(self):
    """Called when agent is about to be replaced (handoff)."""
    pass
```

### Update Methods

```python
# Update instructions dynamically
await agent.update_instructions("New instructions for the agent.")

# Update available tools
await agent.update_tools([new_tool1, new_tool2])

# Update chat context
await agent.update_chat_ctx(new_chat_ctx, exclude_invalid_function_calls=True)
```

### Turn Handling

```python
async def on_user_turn_completed(
    self,
    turn_ctx: llm.ChatContext,
    new_message: llm.ChatMessage
):
    """Called when user completes a turn."""
    # Custom processing of user input
    pass
```

### Pipeline Nodes (Advanced)

Override these methods to customize the processing pipeline:

```python
def stt_node(self, audio, model_settings):
    """Audio transcription pipeline node."""
    async for chunk in audio:
        yield chunk

def llm_node(self, chat_ctx, tools, model_settings):
    """LLM processing pipeline node."""
    # Custom LLM handling
    pass

def transcription_node(self, text, model_settings):
    """Text finalization pipeline node."""
    async for chunk in text:
        if isinstance(chunk, TimedString):
            # Access timing info: chunk.start_time, chunk.end_time
            pass
        yield chunk

def tts_node(self, text, model_settings):
    """Speech synthesis pipeline node."""
    async for chunk in text:
        yield chunk
```

## Complete Example

```python
from livekit.agents import Agent, function_tool, RunContext

class ServiceAgent(Agent):
    def __init__(self, call_data=None, tools=None):
        super().__init__(
            instructions="""You are a service dispatcher for an HVAC company.
            
            Your job is to:
            1. Gather customer information (name, phone, address)
            2. Understand the service issue
            3. Determine urgency
            4. Schedule a technician
            
            Be professional, empathetic, and efficient.""",
            tools=tools or [],
        )
        self.call_data = call_data

    async def on_enter(self):
        """Called when transferred to this agent."""
        await self.session.generate_reply(
            instructions="Acknowledge you understand they need service and start gathering information."
        )

    @function_tool()
    async def schedule_technician(
        self,
        context: RunContext,
        customer_name: str,
        issue_description: str,
        urgency: str,
    ) -> str:
        """Schedule a technician for service."""
        # Implementation
        return f"Technician scheduled for {customer_name}"

    async def on_user_turn_completed(self, turn_ctx, new_message):
        """Process completed user turns."""
        # Extract information from the message
        text = new_message.text_content
        if text:
            # Update call data, check for routing, etc.
            pass
```

## Agent Handoffs

Transfer control between agents:

```python
# In your routing logic
new_agent = ServiceAgent(call_data=call_data)
session.update_agent(new_agent)  # Triggers on_exit() then on_enter()
```

# Function Tools in LiveKit Agents

**Source:** https://docs.livekit.io/agents/build/tools/

## Overview

Function tools allow your agent to execute code based on conversation context. The LLM decides when to call tools based on the conversation and tool descriptions.

## Basic Definition

```python
from livekit.agents import Agent, function_tool, RunContext
from typing import Any

class MyAgent(Agent):
    def __init__(self):
        super().__init__(
            instructions="You are a helpful assistant.",
        )

    @function_tool()
    async def lookup_weather(
        self,
        context: RunContext,
        location: str,
    ) -> dict[str, Any]:
        """Look up weather information for a given location.
        
        Args:
            location: The city or location to look up weather for.
        """
        # Your implementation
        weather_data = await fetch_weather_api(location)
        return {"weather": weather_data["condition"], "temperature_f": weather_data["temp"]}
```

## Key Components

### Parameters
- Tool arguments map automatically from function parameters by name
- Type hints are included when present
- The docstring becomes the tool description for the LLM
- Additional argument details should go in the docstring

### RunContext
Provides access to:
- `context.session` - The AgentSession
- `context.agent` - The current Agent
- `context.function_call` - Details about the function call
- `context.speech_handle` - Handle to current speech
- `context.userdata` - Custom user data

### Return Values
- Return values are automatically converted to strings for the LLM
- Return `None` to complete silently without LLM response
- Can trigger handoffs to other agents

## Advanced Patterns

### Tools with No Return Response

```python
@function_tool()
async def set_reminder(
    self,
    context: RunContext,
    reminder_text: str,
    minutes: int,
) -> None:
    """Set a reminder. No confirmation needed."""
    await schedule_reminder(reminder_text, minutes)
    # Returning None means no LLM response is generated
```

### Error Handling

```python
from livekit.agents import ToolError

@function_tool()
async def book_appointment(
    self,
    context: RunContext,
    date: str,
    time: str,
) -> str:
    """Book an appointment."""
    try:
        result = await booking_api.create(date, time)
        return f"Appointment booked for {date} at {time}"
    except BookingError as e:
        # ToolError communicates issues back to the LLM
        raise ToolError(f"Could not book appointment: {e}")
```

### Dynamic Tool Creation

```python
def create_routing_tools(call_data):
    """Create tools dynamically based on context."""
    
    @function_tool()
    async def transfer_to_billing(context: RunContext) -> str:
        """Transfer the caller to the billing department."""
        call_data.switch_department("billing")
        # Trigger agent handoff
        context.session.update_agent(BillingAgent(call_data))
        return "Transferred to billing"
    
    @function_tool()
    async def transfer_to_service(context: RunContext) -> str:
        """Transfer the caller to the service department."""
        call_data.switch_department("service")
        context.session.update_agent(ServiceAgent(call_data))
        return "Transferred to service"
    
    return [transfer_to_billing, transfer_to_service]
```

### Passing Tools to Agents

```python
# At session level
session = AgentSession(
    tools=[my_tool1, my_tool2],
)

# At agent level
class MyAgent(Agent):
    def __init__(self, tools=None):
        super().__init__(
            instructions="...",
            tools=tools or [],
        )
```

## MCP (Model Context Protocol) Integration

```python
from livekit.agents import mcp

# Load tools from MCP servers
mcp_server = mcp.MCPServer(uri="http://localhost:3000/mcp")

session = AgentSession(
    mcp_servers=[mcp_server],
)
```

## Tool Configuration

### Max Tool Steps

Limit consecutive tool calls per turn:

```python
session = AgentSession(
    max_tool_steps=3,  # Default is 3
)
```

### Updating Tools at Runtime

```python
# Add or remove tools dynamically
await agent.update_tools([new_tool1, new_tool2])
```

## Best Practices

1. **Clear Descriptions** - Write detailed docstrings so the LLM knows when to use each tool
2. **Type Hints** - Always include type hints for parameters
3. **Error Handling** - Use `ToolError` to communicate issues back to the LLM gracefully
4. **Async** - Make tools async for non-blocking execution
5. **Return Useful Info** - Return information the LLM can use in its response
6. **Limit Tool Steps** - Set appropriate `max_tool_steps` to prevent infinite loops

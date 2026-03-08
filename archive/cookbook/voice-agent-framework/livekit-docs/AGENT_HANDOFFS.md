# LiveKit Agent Handoffs (SDK 1.3.x)

Source: https://docs.livekit.io/agents/logic/agents-handoffs/

## Core Concept
A handoff transfers session control from one agent to another. You can return a different 
agent from within a tool call to enable automatic control transfers.

## Python Implementation Pattern

```python
@function_tool()
async def transfer_to_billing(self, context: RunContext):
    """Transfer the customer to a billing specialist."""
    return BillingAgent(chat_ctx=self.chat_ctx), "Transferring to billing"
```

## Key Points
1. Return a TUPLE: (new_agent, message_string)
2. Pass chat_ctx to preserve conversation history
3. The LLM decides when handoffs should occur based on tool descriptions
4. An AgentHandoff item is added to chat context tracking old_agent_id and new_agent_id

## Context Preservation
```python
return TechnicalSupportAgent(chat_ctx=self.session.chat_ctx)
```

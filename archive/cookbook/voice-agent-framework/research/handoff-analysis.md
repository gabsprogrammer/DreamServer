# HVAC Grace: Handoff Analysis

**Date:** February 2, 2026  
**Investigator:** OpenClaw Agent  
**Status:** Analysis Complete

---

## 1. Current Handoff Flow

### Step-by-Step Process

1. **PortalAgent greets caller** → "Thanks for calling Light Heart Mechanical, this is Grace. What can I help you with today?"

2. **Caller explains their issue** → e.g., "My rooftop unit isn't cooling"

3. **PortalAgent acknowledges** → "I understand, let me gather some basic information from you if that's okay."

4. **System routes to specialist** via `route_to_service()`:
   - `call_data.switch_department("service")` is called
   - Returns `(ServiceAgent(call_data, tools), "")` ← **Empty string = no transition message**

5. **ServiceAgent.on_enter() fires immediately**:
   ```python
   if caller_name:
       self.session.say("What's happening with the equipment?", allow_interruptions=True)
   else:
       self.session.say("Can I get your name?", allow_interruptions=True)
   ```

6. **Caller is confused** → They just explained their issue to Portal, now being asked again

---

## 2. Problems Identified

### Problem A: Hardcoded `on_enter` Messages Bypass Context

**Location:** `hvac_agent.py` lines 616-724

Each specialist's `on_enter()` method uses hardcoded `.say()` calls that completely ignore:
- What the caller already told the Portal agent
- Any context passed via `get_specialist_instruction()`
- The conversation history

**Example:**
```python
# ServiceAgent.on_enter()
if caller_name:
    self.session.say("What's happening with the equipment?", allow_interruptions=True)
```

This fires **before** the LLM sees the instructions containing "DO NOT ask for this again."

### Problem B: Empty Transition Messages

**Location:** `hvac_agent.py` lines 799-838

All `route_to_*` tools return an empty string as the second tuple element:
```python
async def route_to_service():
    call_data.switch_department("service")
    return ServiceAgent(call_data, tools=tools_container), ""  # ← Empty!
```

The second element should contain a transition message like "Let me get you to our service team."

### Problem C: Information Re-asking Despite Instructions

While `get_specialist_instruction()` adds context:
```python
# KNOWN CALLER INFORMATION
The following information has already been collected. DO NOT ask for this again.
Caller name: John
Callback number: 555-1234
```

The `on_enter()` method fires **before** the LLM processes these instructions, making the prompt guidance useless for the initial greeting.

### Problem D: Portal Collects Issue But Doesn't Pass It

The Portal agent hears "My rooftop unit isn't cooling" but this isn't stored anywhere accessible to the specialist. The `CallData` class stores:
- `caller_name`, `caller_phone`, `caller_company`, `caller_site`, `caller_role`

But NOT:
- `initial_issue` or `reason_for_call`

### Problem E: Transcript Not Used for Context

`CallData` has `transcript_lines` and `get_full_transcript()`, but this isn't injected into specialist instructions. The new agent has no idea what was already discussed.

---

## 3. Root Causes

| Issue | Root Cause |
|-------|------------|
| Repeated questions | `on_enter()` bypasses LLM/prompt logic |
| Abrupt transitions | Route tools return empty transition string |
| Lost context | Initial issue not captured in CallData |
| Re-asking info | Hardcoded messages ignore collected data |

---

## 4. Recommended Fixes

### Fix 1: Remove Hardcoded `on_enter` Messages (High Priority)

**Option A - Remove entirely:**
```python
async def on_enter(self) -> None:
    pass  # Let the LLM handle the greeting based on instructions
```

**Option B - Make context-aware:**
```python
async def on_enter(self) -> None:
    # Only speak if we have zero context
    if not self._call_data.caller_name and not self._call_data.transcript_lines:
        self.session.say("Can I get your name?", allow_interruptions=True)
    # Otherwise, let the LLM craft an appropriate response
```

### Fix 2: Add Transition Messages to Route Tools

```python
@function_tool()
async def route_to_service():
    """Route to service team for equipment repairs, breakdowns, emergencies"""
    call_data.switch_department("service")
    return ServiceAgent(call_data, tools=tools_container), "Let me gather some details for our service team."

@function_tool()
async def route_to_billing():
    """Route to billing team for invoice questions, payments, disputes"""
    call_data.switch_department("billing")
    return BillingAgent(call_data, tools=tools_container), "I can help you with that billing question."
```

### Fix 3: Capture Initial Issue in CallData

Add to `CallData` class:
```python
@dataclass
class CallData:
    # ... existing fields ...
    initial_issue: str = ""  # What the caller said they need
    
    def set_initial_issue(self, issue: str):
        if not self.initial_issue:  # Only set once
            self.initial_issue = issue
```

Update `get_caller_context()`:
```python
def get_caller_context(self) -> str:
    parts = []
    if self.caller_name:
        parts.append(f"Caller name: {self.caller_name}")
    # ... existing fields ...
    if self.initial_issue:
        parts.append(f"Reason for call: {self.initial_issue}")
    return "\n".join(parts) if parts else "No caller info collected yet."
```

### Fix 4: Inject Recent Transcript into Specialist Prompts

In `get_specialist_instruction()`:
```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    base = base_instructions.get(intent, OFFICE_INSTRUCTION)
    
    # Add caller context
    caller_context = call_data.get_caller_context()
    if caller_context != "No caller info collected yet.":
        context_section = f"""

# KNOWN CALLER INFORMATION
{caller_context}
"""
        base = base + context_section
    
    # Add recent transcript (last 5 lines)
    if call_data.transcript_lines:
        recent = call_data.transcript_lines[-5:]
        transcript_section = f"""

# RECENT CONVERSATION
The caller has already said the following. DO NOT ask them to repeat this.
{chr(10).join(recent)}
"""
        base = base + transcript_section
    
    return base + CLOSING_SEQUENCE
```

### Fix 5: Update Specialist Prompts for Handoff Awareness

Add to each specialist prompt:
```
# HANDOFF AWARENESS
You are receiving this caller from another team member. They may have already explained their issue.
- Reference what they said: "You mentioned your rooftop unit - let me get the details for a service ticket."
- Don't ask for information they already provided
- Build on the conversation, don't restart it
```

---

## 5. Implementation Priority

1. **Quick Win:** Add transition messages to `route_to_*` tools (5 min)
2. **Medium Fix:** Remove/modify `on_enter()` hardcoded messages (15 min)
3. **Full Fix:** Add `initial_issue` to CallData + transcript injection (30 min)

---

## 6. Expected Outcome

### Before (Current - Messy):
> **Portal:** What can I help you with today?  
> **Caller:** My rooftop unit isn't cooling.  
> **Portal:** I understand, let me gather some basic information.  
> *[silent switch]*  
> **Service:** What's happening with the equipment?  
> **Caller:** I just told you...

### After (Fixed - Smooth):
> **Portal:** What can I help you with today?  
> **Caller:** My rooftop unit isn't cooling.  
> **Portal:** I understand, let me gather some details for our service team.  
> *[transition message plays]*  
> **Service:** You mentioned your rooftop unit isn't cooling - let me get a ticket started. Can I get your name?  
> **Caller:** John Smith.

---

*Report generated by OpenClaw Investigation Agent*

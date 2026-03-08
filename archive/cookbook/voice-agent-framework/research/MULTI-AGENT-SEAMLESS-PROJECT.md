# Project: Seamless Multi-Agent Grace

**Created:** February 2, 2026  
**Architecture:** Multi-Agent with Enhanced Coordination  
**Key Constraint:** Single-agent approach was attempted and failed. This plan is built on multi-agent.

---

## Vision

Callers interact with **ONE person—Grace**—throughout their entire call. They never experience:
- Obvious transfers or handoffs
- Being asked to repeat information
- Personality shifts between topics
- Awkward silences during transitions

The multi-agent architecture remains invisible to callers. Internal routing happens silently while Grace's personality stays consistent.

---

## Why Multi-Agent (Not Single-Agent)

### V2 Postmortem: What Went Wrong with Single-Agent

The single-agent approach was previously attempted with these outcomes:

1. **Prompt Complexity Explosion**
   - Combining all domain knowledge (service, billing, parts, projects, maintenance, controls) into one prompt exceeded reasonable token limits
   - The LLM struggled to maintain focus when all contexts were active simultaneously
   - Edge cases multiplied: the LLM had to juggle service urgency rules + billing restrictions + parts procedures + controls technical knowledge all at once

2. **Domain Mode Confusion**
   - Without explicit agent boundaries, the LLM would blur domains
   - Example: Applying after-hours emergency logic to billing questions
   - Example: Attempting technical troubleshooting for invoice disputes
   - The "activate_X_mode" tool approach didn't provide clean enough separation

3. **Testing & Debugging Nightmare**
   - Single monolithic prompt was hard to test in isolation
   - Changes to service handling affected billing behavior unexpectedly
   - No clear boundaries for unit testing domain-specific logic

4. **Context Window Pressure on Long Calls**
   - Single agent accumulated all conversation history
   - Multi-topic calls (service + billing + parts) exhausted context faster
   - No natural summarization points between topics

5. **LiveKit Integration Complexity**
   - Single agent required complex internal state tracking
   - Harder to leverage LiveKit's built-in agent lifecycle
   - Lost the clean "specialist takes over" pattern

### Why Multi-Agent Works (When Done Right)

The current multi-agent architecture has **structural advantages**:
- Clean domain separation in prompts
- Each specialist has focused, testable instructions
- LiveKit's agent swap mechanism is well-supported
- Modular additions (new specialist) don't break existing ones
- Context can be strategically pruned between handoffs

**The problem isn't multi-agent. The problem is visible seams.**

---

## Current Multi-Agent Strengths

✅ **Clean Domain Separation**
- Each specialist has focused instructions
- Service knows emergency vs. non-emergency handling
- Billing knows what it can/can't do with invoices
- Parts knows ticket-based inquiry flow

✅ **LiveKit Native Integration**
- Uses standard `session.update_agent()` pattern
- `on_enter()` lifecycle is well-defined
- Voice session management is handled by framework

✅ **Modular Testing**
- Can test Service prompts independently
- Can simulate handoffs in isolation
- Clear boundaries for regression testing

✅ **TTS Filter Already Works**
- Transfer announcements are already filtered
- "I've routed your request" → silent
- "Let me transfer you to" → filtered out

✅ **CallData Persists Correctly**
- Name, phone, company, site carry across agents
- Departments visited is tracked
- Transcript captured in real-time

---

## Current Multi-Agent Weaknesses (The Seams)

### Seam 1: Hardcoded on_enter() Greetings
**Location:** `hvac_agent.py` lines 624-731

Each specialist has:
```python
async def on_enter(self) -> None:
    if caller_name:
        self.session.say("What's happening with the equipment?")
    else:
        self.session.say("Can I get your name?")
```

**Problem:** Caller just told Portal what's happening. ServiceAgent immediately re-asks.

### Seam 2: Dead Air During Transfer
**Location:** `hvac_agent.py` line 1083

```python
await asyncio.sleep(1.0)  # Fixed 1-second silence
```

**Problem:** Awkward pause. Caller wonders if they were disconnected.

### Seam 3: Transcript Not in LLM Context
**Location:** `get_specialist_instruction()` function

The specialist receives:
- Name, phone, company, site ✓
- What the caller actually said ✗

**Problem:** LLM has no idea what caller discussed with Portal. Can't continue naturally.

### Seam 4: Personality Inconsistencies
**Location:** Various `prompts/*.py` files

| Specialist | Personality |
|------------|-------------|
| Billing | "Professional and patient" |
| Parts | "Helpful and understanding" |
| Service | (none specified) |
| Controls | "Technical and patient" |

**Problem:** Grace feels like different people for different topics.

### Seam 5: Opening Line Conflicts
**Location:** Prompts vs on_enter()

- Prompt says: "YOUR OPENING: I can help with that..."
- on_enter() says: "Can I get your name?"

**Problem:** Double-speak or contradiction.

### Seam 6: No Conversation Continuity Markers
**Location:** Specialist prompts

No instruction like: "Continue from where the caller left off. Do not re-introduce yourself."

**Problem:** LLM treats each handoff as a fresh conversation.

---

## Architecture Decision: Multi-Agent with Enhanced Coordination

### Pattern: Specialist Agents with Context Injection

Keep the existing multi-agent structure, but enhance it with:

1. **Full Context Handoff** - Inject transcript and caller statement into specialist prompt
2. **Silent Transitions** - Remove/modify on_enter() hardcoded speeches
3. **Personality Synchronization** - Unified Grace identity across all prompts
4. **Seamless Opening** - Specialist continues conversation, doesn't restart it

### Context Flow Diagram

```
BEFORE (Current):
┌─────────┐   CallData only    ┌────────────┐
│ Portal  │ ─────────────────► │ Specialist │
└─────────┘   (name, phone)    └────────────┘
              ▲
              │ Lost: what caller said, why we routed

AFTER (Enhanced):
┌─────────┐   Full Context     ┌────────────┐
│ Portal  │ ─────────────────► │ Specialist │
└─────────┘   • CallData       └────────────┘
              • Transcript
              • Routing reason
              • Initial request
              • Continuity markers
```

---

## Implementation Phases

### Phase 1: Context Flow Enhancement (3-4 hours)

**Goal:** Specialist agents know what was said before they took over.

#### 1.1 Enhance CallData with Handoff Context
**File:** `hvac_agent.py` (CallData class)

```python
# ADD these fields to CallData
@dataclass  
class CallData:
    # ... existing fields ...
    
    # NEW: Handoff context
    initial_request: str = ""        # What caller said that triggered routing
    routing_reason: str = ""         # Why we routed (intent detected)
    last_grace_statement: str = ""   # What Grace said before handoff
    handoff_context_summary: str = "" # Brief summary for specialist
    
    def set_handoff_context(self, caller_statement: str, intent: str, grace_response: str):
        """Capture full context for seamless handoff."""
        self.initial_request = caller_statement
        self.routing_reason = intent
        self.last_grace_statement = grace_response
        self.handoff_context_summary = f"Caller needs help with {intent}: {caller_statement}"
```

#### 1.2 Capture Context at Routing Point
**File:** `hvac_agent.py` (around line 1060, in perform_transfer)

```python
async def perform_transfer(session, intent, context, call_data):
    # NEW: Capture handoff context before transfer
    call_data.set_handoff_context(
        caller_statement=context,  # This param exists but is unused!
        intent=intent,
        grace_response=call_data.transcript_lines[-1] if call_data.transcript_lines else ""
    )
    
    # REMOVE: await asyncio.sleep(1.0)  # No more dead air
    
    new_agent = agent_class(call_data, tools=routing_tools)
    session.update_agent(new_agent)
```

#### 1.3 Inject Full Context into Specialist Prompts
**File:** `hvac_agent.py` (get_specialist_instruction function)

```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    base = base_instructions.get(intent, OFFICE_INSTRUCTION)
    
    # Existing: caller context (name, phone, etc.)
    caller_context = call_data.get_caller_context()
    if caller_context != "No caller info collected yet.":
        context_section = f"""
# KNOWN CALLER INFORMATION (DO NOT RE-ASK)
{caller_context}
"""
        base = base + context_section
    
    # NEW: Conversation history injection
    conversation_context = build_conversation_context(call_data)
    base = base + conversation_context
    
    return base + CLOSING_SEQUENCE

def build_conversation_context(call_data: CallData) -> str:
    """Build the conversation context for seamless continuation."""
    parts = []
    
    # Recent transcript (last 20 lines to manage tokens)
    if call_data.transcript_lines:
        recent = call_data.transcript_lines[-20:]
        transcript_text = "\n".join(recent)
        parts.append(f"""
# CONVERSATION SO FAR
{transcript_text}
""")
    
    # Handoff context
    if call_data.initial_request:
        parts.append(f"""
# WHAT THE CALLER NEEDS
The caller said: "{call_data.initial_request}"
This is why you're helping them now. Acknowledge and continue - do NOT ask them to repeat.
""")
    
    # Continuity instruction
    parts.append("""
# CRITICAL: SEAMLESS CONTINUATION
- You ARE Grace. The caller has been talking to you the whole time.
- Do NOT re-introduce yourself. Do NOT say "I can help with that."
- Do NOT ask for information already provided in the conversation.
- Continue naturally as if the conversation never paused.
- Your first response should acknowledge what they said and move forward.
""")
    
    return "\n".join(parts)
```

### Phase 2: Transition Smoothing (2-3 hours)

**Goal:** Eliminate hardcoded on_enter() announcements, let LLM continue naturally.

#### 2.1 Remove Hardcoded on_enter() Speeches
**File:** `hvac_agent.py` lines 624-731

**BEFORE:**
```python
class ServiceAgent(Agent):
    async def on_enter(self) -> None:
        caller_name = self._call_data.caller_name if self._call_data else None
        if caller_name:
            self.session.say("What's happening with the equipment?", allow_interruptions=True)
        else:
            self.session.say("Can I get your name?", allow_interruptions=True)
```

**AFTER:**
```python
class ServiceAgent(Agent):
    async def on_enter(self) -> None:
        # Let the LLM continue naturally based on injected context
        # No hardcoded speech - the prompt tells LLM to acknowledge and continue
        pass
```

Apply this change to: ServiceAgent, BillingAgent, PartsAgent, ProjectsAgent, ControlsAgent, MaintenanceAgent, GeneralAgent

#### 2.2 Update Specialist Prompt Openings
**Files:** `prompts/service.py`, `prompts/billing.py`, etc.

**REMOVE lines like:**
```
# YOUR OPENING (say this immediately when you connect)
"I can help with that. What's your name and a callback number?"
```

**REPLACE with:**
```
# YOUR FIRST RESPONSE
Based on what the caller just said, acknowledge their request and gather any missing information.
Do NOT use a scripted opening. Respond to what they actually said.

Example good responses:
- "Got it, [issue they described]. Let me get a few details to get a tech out there."
- "I see - [their concern]. What's the invoice number?"
- "Understood. What site is this for?"

Example BAD responses (DO NOT USE):
- "I can help with that." (too generic)
- "What's your name and callback number?" (ignores what they said)
- "Thanks for calling, how can I help?" (re-greeting)
```

#### 2.3 Remove Dead Air Sleep
**File:** `hvac_agent.py` line 1083

```python
# DELETE this line:
await asyncio.sleep(1.0)
```

#### 2.4 Add Bridge Phrase (Optional Enhancement)
**File:** `hvac_agent.py` in perform_transfer

If complete silence feels abrupt, add a non-announcement bridge:
```python
async def perform_transfer(session, intent, context, call_data):
    call_data.set_handoff_context(context, intent, "")
    
    # Optional: Brief non-announcement bridge (if testing shows silence is awkward)
    # session.say("Got it.", allow_interruptions=True)
    
    new_agent = agent_class(call_data, tools=routing_tools)
    session.update_agent(new_agent)
```

### Phase 3: Personality Unification (2-3 hours)

**Goal:** Grace sounds like the same person regardless of topic.

#### 3.1 Create Shared Grace Identity Block
**File:** `prompts/shared.py` (new file)

```python
GRACE_IDENTITY = """
# WHO YOU ARE
You are Grace, answering the phone for {company_name}, a commercial HVAC contractor.

You're warm, professional, and efficient. You don't waste callers' time, but you're not cold.
You're ONE person throughout the entire call - if a caller discusses multiple topics, 
you handle them all yourself. You never say "let me transfer you" or make the caller 
feel like they're being bounced between departments.

# HOW YOU SPEAK
- One question at a time (NEVER combine questions)
- Natural contractions: "I'll", "we'll", "what's", "you're"
- Brief acknowledgments: "Got it." "I see." "Okay."
- Confirm what you heard: "A rooftop unit not cooling, got it."
- Read back numbers: "That's 5-5-5, 1-2-3-4?"

# WHAT YOU NEVER DO
- Ask multiple questions at once
- Re-ask for information already provided
- Announce transfers or departments ("let me connect you to billing")
- Use internal terms: "agent", "specialist", "system", "routing", "ticket"
- Promise specific prices, arrival times, or availability
- Sound robotic or scripted
"""
```

#### 3.2 Standardize All Specialist Prompts
**Files:** All `prompts/*.py`

**Structure for each specialist:**
```python
from prompts.shared import GRACE_IDENTITY

SERVICE_INSTRUCTION = f"""
{GRACE_IDENTITY}

# YOUR CURRENT FOCUS: Service/Equipment Issues
[Domain-specific guidance here]

# REQUIRED INFORMATION
[What to collect]

# TIME-BASED RESPONSES  
[Business hours vs after-hours handling]
"""
```

#### 3.3 Remove Conflicting Personality Descriptions
**Files:** `prompts/billing.py`, `prompts/parts.py`, etc.

**REMOVE lines like:**
- "Be professional and patient"
- "Be helpful and understanding"
- "Be technical and patient"

The shared GRACE_IDENTITY handles personality. Domain prompts handle domain knowledge only.

#### 3.4 Add Continuity Markers to All Prompts
**Files:** All specialist prompts

**Add to each specialist prompt:**
```
# CONVERSATION CONTINUITY
Remember: You've been talking to this caller the whole time (as Grace).
- Reference things they mentioned earlier if relevant
- Don't introduce yourself again
- When finishing this topic, check if they mentioned other issues: "Now, you also mentioned [X]..."
```

### Phase 4: Testing & Tuning (2-3 hours)

#### 4.1 Test Scenarios

**Scenario A: Simple Routing**
1. Caller: "Hi, our AC is broken"
2. Portal detects service intent, routes
3. Service: Should say something like "Got it, AC issue. What site is this at?" (NOT "Can I get your name?")

**Scenario B: Multi-Topic Call**
1. Caller: "I have an AC down and also a billing question"
2. Portal routes to service (urgency)
3. Service handles equipment, then: "Now, you mentioned a billing question - what's that about?"
4. Billing handles invoice (NOT "Can I get your name?")

**Scenario C: Context Preservation**
1. Caller to Portal: "This is John from ABC Company, our RTU at Main Street is down"
2. Routes to Service
3. Service should NOT ask for name, company, or site - all were stated

**Scenario D: Tone Matching**
1. Frustrated caller: "I've been waiting a week for this part!"
2. Parts agent should acknowledge frustration, not say "I can help with that"

#### 4.2 Success Metrics Validation

- [ ] Caller never hears "let me transfer you" or similar
- [ ] Caller never asked to repeat name/phone/site
- [ ] No awkward silence >0.5s during handoffs
- [ ] Grace's tone consistent across all topics
- [ ] Multi-topic calls handled without "starting over"
- [ ] Closing recap references actual issues discussed

#### 4.3 Regression Testing

- [ ] Service tickets still created correctly
- [ ] After-hours logic still works
- [ ] Urgency detection still triggers emergency flow
- [ ] TTS filter still catches any slip-through routing language
- [ ] Call recording and transcript extraction still work

---

## Detailed Code Changes Summary

### Files to Modify

| File | Changes |
|------|---------|
| `hvac_agent.py` | Add CallData fields, modify get_specialist_instruction(), remove on_enter() speeches, remove dead air sleep |
| `prompts/service.py` | Add shared identity, remove scripted opening |
| `prompts/billing.py` | Add shared identity, remove scripted opening, remove personality line |
| `prompts/parts.py` | Add shared identity, remove scripted opening, remove personality line |
| `prompts/projects.py` | Add shared identity, remove scripted opening |
| `prompts/controls.py` | Add shared identity, remove scripted opening, remove personality line |
| `prompts/maintenance.py` | Add shared identity, remove scripted opening |
| `prompts/general.py` | Add shared identity, remove scripted opening, remove personality line |

### New Files

| File | Purpose |
|------|---------|
| `prompts/shared.py` | GRACE_IDENTITY and common prompt fragments |

### Lines to Delete

| Location | What |
|----------|------|
| `hvac_agent.py:1083` | `await asyncio.sleep(1.0)` |
| `hvac_agent.py:624-731` | All `session.say()` calls in `on_enter()` methods |
| Various prompts | "YOUR OPENING: I can help with that..." sections |
| Various prompts | "Be professional and patient" personality lines |

---

## Success Metrics

### Quantitative
- **Repeat questions:** 0 instances of re-asking name/phone/site that was already provided
- **Dead air:** <0.5 seconds during any handoff
- **Transfer announcements:** 0 (TTS filter catch rate stays at 100%)

### Qualitative  
- **Blind test:** Play call recordings to someone unfamiliar with system. They should not be able to identify when handoffs occur.
- **Personality consistency:** Grace should sound identical whether discussing service or billing.
- **Natural transitions:** Topic changes should feel like a human receptionist smoothly switching gears.

---

## Estimated Effort

| Phase | Time | Risk |
|-------|------|------|
| Phase 1: Context Flow | 3-4 hours | Low - Additive changes |
| Phase 2: Transition Smoothing | 2-3 hours | Medium - Behavior changes |
| Phase 3: Personality Unification | 2-3 hours | Low - Prompt updates |
| Phase 4: Testing & Tuning | 2-3 hours | Medium - May need iteration |
| **Total** | **9-13 hours** | |

**Recommended approach:**
1. Implement Phase 1 & 2 together (core seamlessness)
2. Test thoroughly before Phase 3
3. Phase 3 can be done incrementally per specialist
4. Phase 4 runs throughout

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Transcript injection makes prompts too long | Medium | Medium | Limit to last 20 lines, summarize if >3 minutes |
| LLM ignores continuity instructions | Low | High | Strong prompt language, test multiple phrasings |
| Removing on_enter() causes silence | Medium | Low | Add optional bridge phrase "Got it" |
| Multi-agent timing race conditions | Low | Medium | Test handoff timing, add small buffer if needed |
| Breaking existing ticket flow | Low | High | Full regression test before deploy |

---

## Post-Implementation Monitoring

After deployment, monitor for:
1. **Call duration changes** - Should be slightly shorter (less repetition)
2. **Caller interruptions** - Fewer "I already told you" moments  
3. **Ticket accuracy** - Same or better field population
4. **User feedback** - Callers shouldn't notice the change (that's success)

---

*Multi-Agent Seamless Project Plan*  
*Preserving architecture strength while eliminating visible seams*  
*February 2, 2026*

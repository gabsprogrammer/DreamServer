# HVAC Grace - Technical Architecture for Seamless Handoffs

**Research Date:** February 2, 2026  
**Current System:** LiveKit Agents 1.3.12, Multi-Agent with CallData State

---

## Executive Summary

This document analyzes three architectural approaches for enabling seamless, invisible agent handoffs while maintaining Grace's consistent personality. After thorough analysis of the current codebase and LiveKit constraints, **Alternative A (Single Agent with Tool Specialization)** is recommended as the optimal path forward.

---

## 1. Analysis of Single vs Multi-Agent Approaches

### Current Architecture: Multi-Agent with Shared State

```
PortalAgent → ServiceAgent → ClosingAgent
         ↓
     CallData (shared state)
```

**How it works:**
- Each specialist is a separate `Agent` class with distinct `instructions`
- `CallData` dataclass persists across all handoffs (name, phone, company, transcript)
- `session.update_agent(new_agent)` swaps the active agent
- Each agent has an `on_enter()` method that speaks an opening line
- Routing tools return `(NewAgent, "")` to trigger handoff

**Current Problems:**
1. **Announcement leak**: `on_enter()` speaks a scripted phrase, revealing the transfer
2. **Context reset**: New agent only sees injected context, not conversation flow
3. **Personality fragmentation**: Each agent prompt defines Grace separately
4. **Hard transitions**: Moving from one topic to another feels abrupt

---

### Alternative A: Single Agent with Tool Specialization ⭐ RECOMMENDED

**Architecture:**
```
One Grace Agent
    ├── Core Tools (always available)
    │   ├── route_to_service()  → inject specialist knowledge
    │   ├── route_to_billing()  → inject specialist knowledge  
    │   └── route_to_closing()  → inject closing sequence
    └── Domain Tools (dynamically enabled)
        ├── Service: create_service_ticket(), check_tech_availability()
        ├── Billing: lookup_invoice(), process_payment()
        └── Parts: check_part_status(), order_part()
```

**How it would work:**
- Single `GraceAgent` with comprehensive base personality
- Tools return **knowledge injection** (strings), not new agents
- The LLM decides tool usage based on conversation context
- No handoffs — just different tool invocations
- Conversation history stays intact throughout

**Implementation Concept:**
```python
class GraceAgent(Agent):
    def __init__(self, call_data: CallData):
        super().__init__(
            instructions=GRACE_UNIFIED_INSTRUCTION,
            tools=[
                # Knowledge tools - inject specialist context
                self.activate_service_mode,
                self.activate_billing_mode,
                self.activate_parts_mode,
                # Action tools - domain-specific operations
                self.create_ticket,
                self.lookup_customer,
                self.check_part_status,
            ]
        )
        self._call_data = call_data
        self._active_mode = "general"

    @function_tool()
    async def activate_service_mode(self) -> str:
        """Activate service specialist knowledge for equipment issues."""
        self._call_data.switch_department("service")
        return SERVICE_KNOWLEDGE  # Returns knowledge string, not an agent
```

**Pros:**
- ✅ Zero perceptible handoffs — it's one continuous conversation
- ✅ Full conversation history always available to LLM
- ✅ Single personality definition = perfect consistency
- ✅ Natural topic transitions ("Actually, while I have you...")
- ✅ Simpler codebase — no agent class proliferation
- ✅ LLM can blend expertise when topics overlap

**Cons:**
- ⚠️ Larger system prompt (all specialist knowledge in one place)
- ⚠️ Tool routing relies on LLM judgment, not explicit keywords
- ⚠️ May need prompt engineering to prevent mode confusion

**Token Impact:**
- Current: ~800 tokens per specialist prompt
- Single agent: ~2,500 tokens unified prompt (acceptable for Claude/GPT-4)

---

### Alternative B: Multi-Agent with Shared State (Enhanced)

**Architecture:**
```
Same as current, but enhanced:
    ├── Full transcript injected (not just CallData summary)
    ├── Eliminate on_enter() announcements
    └── Add conversation style continuity markers
```

**Improvements over current:**
```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    base = SPECIALIST_PROMPTS[intent]
    
    # Inject FULL transcript, not just extracted fields
    transcript_injection = f"""
# CONVERSATION SO FAR
{call_data.get_full_transcript()}

# IMPORTANT: Continue naturally from this conversation.
# Do NOT announce yourself. Do NOT re-introduce.
# The caller doesn't know you're a different specialist.
"""
    return base + transcript_injection
```

**Pros:**
- ✅ Preserves existing architecture investment
- ✅ Full context through transcript injection
- ✅ Specialists can have truly focused prompts

**Cons:**
- ❌ Still has agent swap overhead
- ❌ `on_enter()` timing issues remain
- ❌ Personality consistency requires careful prompt management
- ❌ Transcript injection grows large over time
- ❌ Context window limits with long calls

---

### Alternative C: Orchestrator + Specialists (Hidden Functions)

**Architecture:**
```
Grace Orchestrator (user-facing)
    │
    ├── Internal Function: service_specialist(question)
    ├── Internal Function: billing_specialist(question)  
    └── Internal Function: parts_specialist(question)
```

**How it would work:**
- One Grace orchestrator handles ALL user interaction
- Specialist "functions" are called internally, return structured data
- Grace synthesizes responses from specialist function outputs
- Functions don't have their own LLM — they're deterministic helpers

**Implementation Concept:**
```python
@function_tool()
async def get_service_guidance(issue: str, urgency: str) -> str:
    """Get service-specific guidance for an equipment issue."""
    if urgency == "emergency":
        return json.dumps({
            "response_template": "Our on-call tech will call you back within 30-60 minutes.",
            "required_fields": ["site", "contact_name", "callback_number"],
            "ticket_priority": "emergency"
        })
    else:
        return json.dumps({
            "response_template": "We'll have someone reach out first thing tomorrow.",
            "required_fields": ["site", "issue_description"],
            "ticket_priority": "normal"
        })
```

**Pros:**
- ✅ Perfect user experience — one voice throughout
- ✅ Specialists as pure knowledge functions, not conversation participants
- ✅ Clear separation of concerns

**Cons:**
- ❌ Loses LLM reasoning in specialist functions (they become rigid)
- ❌ Grace orchestrator prompt becomes complex (managing all domains)
- ❌ Two-stage reasoning adds latency
- ❌ Harder to add nuanced specialist behavior

---

## 2. Recommended Architecture: Single Agent with Tool Specialization

### Rationale

1. **Seamlessness is the priority**: The user explicitly wants "invisible handoffs." A single agent achieves this by design.

2. **LiveKit constraints**: `session.update_agent()` triggers `on_enter()`, which creates an inherent announcement point. Avoiding agent swaps eliminates this.

3. **Grace is one personality**: Having one agent with one prompt ensures consistent voice, tone, and behavior.

4. **Context preservation**: Modern LLMs handle 8K-32K+ context windows. A 15-minute call transcript is ~1,500 tokens. Keeping it in one agent's history is feasible.

5. **Implementation simplicity**: Removing 9 agent classes in favor of one reduces maintenance burden.

---

## 3. State Management Design

### Current CallData (Keep and Enhance)

```python
@dataclass
class CallData:
    # ─────────────────────────────────────────────────────────────
    # IDENTITY (carry across entire call)
    # ─────────────────────────────────────────────────────────────
    room_name: str = ""
    call_start: datetime = field(default_factory=datetime.now)
    
    # Caller basics
    caller_name: str = ""
    caller_phone: str = ""
    caller_company: str = ""
    caller_site: str = ""
    caller_role: str = ""
    
    # Recognition (if matched to existing customer)
    customer_id: Optional[int] = None
    is_recognized: bool = False
    
    # ─────────────────────────────────────────────────────────────
    # CONVERSATION FLOW (new additions)
    # ─────────────────────────────────────────────────────────────
    current_mode: str = "general"  # service | billing | parts | etc.
    active_topics: List[str] = field(default_factory=list)  # Track parallel issues
    
    # Emotional/tone tracking
    sentiment: str = "neutral"  # frustrated | neutral | happy
    urgency_level: str = "normal"  # normal | urgent | emergency
    
    # ─────────────────────────────────────────────────────────────
    # COLLECTED DATA (structured)
    # ─────────────────────────────────────────────────────────────
    tickets_in_progress: Dict[str, dict] = field(default_factory=dict)
    # e.g., {"service": {"site": "Main Plant", "issue": "RTU down"}}
    
    completed_tickets: List[dict] = field(default_factory=list)
    
    # ─────────────────────────────────────────────────────────────
    # TRANSCRIPT (full conversation)
    # ─────────────────────────────────────────────────────────────
    transcript_lines: List[str] = field(default_factory=list)
    
    # ─────────────────────────────────────────────────────────────
    # UNRESOLVED (explicit tracking)
    # ─────────────────────────────────────────────────────────────
    pending_questions: List[str] = field(default_factory=list)
    # e.g., ["need callback number", "need site confirmation"]
```

### State That Should Flow Seamlessly

| State Element | Current | Recommendation |
|--------------|---------|----------------|
| Caller identity | ✅ CallData | Keep - already persists |
| Conversation history | ⚠️ transcript_lines | Enhance - add speaker labels, timestamps |
| Collected information | ✅ CallData fields | Keep - already persists |
| Intent/reason | ❌ Lost on transfer | Add `current_mode` + `active_topics` |
| Current stage | ⚠️ Implicit | Add explicit `conversation_stage` enum |
| Sentiment/tone | ❌ Not tracked | Add `sentiment`, `urgency_level` |
| Unresolved questions | ❌ Not tracked | Add `pending_questions` list |

---

## 4. Prompt Structure Recommendation

### Option A: Layered Prompt (Recommended)

```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 1: Grace's Core Personality (Always Present)             │
│ - Who she is, tone, speaking style                             │
│ - Universal rules (one question at a time, don't re-ask)       │
│ - Company info (Light Heart Mechanical)                        │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 2: Caller Context (Dynamic)                              │
│ - Known info: name, phone, company, site                       │
│ - Recognition status and history                               │
│ - Current mode and active topics                               │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 3: Mode-Specific Knowledge (Injected by Tool)            │
│ - Specialist guidance for current topic                        │
│ - Required fields for ticket creation                          │
│ - Time-sensitive responses (after-hours, etc.)                 │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 4: Pending Actions (Dynamic)                             │
│ - Questions still to ask                                       │
│ - Topics to circle back to                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Unified Grace Prompt Structure

```python
GRACE_CORE_PERSONALITY = """You are Grace, answering the phone for {company_name}, a commercial HVAC contractor.

# WHO YOU ARE
- Warm, professional, efficient
- You sound like a real human receptionist, not a bot
- You adapt to caller's tone (urgent gets efficient, casual gets friendly)

# HOW YOU SPEAK
- Natural contractions: "I'll", "we'll", "what's"
- Brief acknowledgments: "Got it", "I see", "Okay"
- One question at a time — NEVER combine
- Don't repeat yourself — track what you've already asked

# UNIVERSAL RULES
1. If you have info, don't re-ask: "Got it, {name}. What site is this for?"
2. Acknowledge what you hear: "A makeup air unit tripping, got it."
3. Never announce departments, transfers, or internal routing
4. Never speak tool names or function names aloud

# TIME CONTEXT
Current: {current_time}
Business hours: 7 AM - 5 PM weekdays
"""

def build_grace_prompt(call_data: CallData, mode_knowledge: str = "") -> str:
    """Build complete Grace prompt with all layers."""
    
    # Layer 1: Core personality
    prompt = GRACE_CORE_PERSONALITY.format(
        company_name=COMPANY_NAME,
        current_time=datetime.now().strftime("%A, %B %d at %I:%M %p")
    )
    
    # Layer 2: Caller context
    if call_data.caller_name or call_data.caller_phone:
        prompt += f"""
# CALLER INFO (already collected - don't re-ask)
{call_data.get_caller_context()}
"""
    
    if call_data.is_recognized:
        prompt += f"""
# RECOGNIZED CUSTOMER
This is a returning caller. Greet warmly by name.
Previous calls: {call_data.customer_history}
"""
    
    # Layer 3: Mode-specific knowledge (from tool injection)
    if mode_knowledge:
        prompt += f"""
# CURRENT FOCUS: {call_data.current_mode.upper()}
{mode_knowledge}
"""
    
    # Layer 4: Pending actions
    if call_data.pending_questions:
        prompt += f"""
# STILL NEED TO COLLECT
{chr(10).join('- ' + q for q in call_data.pending_questions)}
"""
    
    return prompt
```

---

## 5. Transition Mechanics Design

### Key Question: Should there be ANY user-facing transition?

**Answer: No explicit transition, but natural conversation steering.**

### Transition Types

#### Type 1: Topic Pivot (Most Common)

**Caller:** "...so we need someone out today. Oh, and I've been meaning to ask about our PM agreement."

**Grace (without transition):** "I've got the service request noted. On the PM agreement — are you looking to renew, or do you have a question about the current schedule?"

**Implementation:**
```python
# LLM naturally continues. No mode switch announcement.
# Tool adds maintenance knowledge to context.
# Grace weaves it into conversation.
```

#### Type 2: Initial Routing (Portal → Specialist)

**Current (problematic):**
```
Portal: "Let me connect you with service."
[silence]
Service: "What's happening with the equipment?"
```

**Recommended:**
```
Grace: "Got it, sounds like an equipment issue. What's going on?"
[No transfer — same Grace, same voice, same context]
```

**Implementation:**
```python
# PortalAgent no longer exists
# Grace handles greeting AND intake
# When service tools are invoked, SERVICE_KNOWLEDGE is injected
# Grace continues seamlessly
```

#### Type 3: Mid-Sentence Topic Change

**Caller:** "Actually, forget the billing thing, we've got a unit down."

**Grace:** "Understood — equipment down takes priority. What site and what's happening?"

**Implementation:**
```python
# LLM detects topic shift
# call_data.active_topics updated
# Previous topic marked pending or dropped
# Urgency trumps admin
```

### How Transitions Work Mechanically

```python
# Tool approach — returns context injection, not agent swap

@function_tool()
async def activate_service_mode(
    issue_description: str,
    apparent_urgency: str
) -> str:
    """
    Activate service specialist knowledge when caller has an equipment issue.
    Call this when the conversation shifts to equipment repairs/emergencies.
    """
    call_data.switch_department("service")
    call_data.pending_questions = get_service_required_fields(call_data)
    
    # Return knowledge injection (prompt addition), not a new agent
    return f"""
SERVICE SPECIALIST ACTIVE
Required fields: site, issue details, urgency, callback contact
Current urgency: {apparent_urgency}
After-hours policy: On-call tech returns calls within 30-60 min for emergencies.
"""
```

### Voice Continuity

**Critical**: Same TTS voice throughout. Current system already does this via shared `FilteredTTS`.

```python
# This is correct and should remain:
tts = FilteredTTS(raw_tts)  # Same voice for all agents
```

---

## 6. Implementation Complexity Estimates

### Option A: Single Agent with Tool Specialization ⭐

| Task | Effort | Notes |
|------|--------|-------|
| Create unified `GraceAgent` class | 2 hours | Replace 9 agent classes with 1 |
| Build `GRACE_UNIFIED_INSTRUCTION` prompt | 3 hours | Merge and dedupe specialist prompts |
| Convert routing tools to knowledge injectors | 2 hours | Change return type from Agent to str |
| Remove `on_enter()` announcements | 0.5 hours | Delete the methods |
| Add mode tracking to CallData | 1 hour | New fields + switch logic |
| Update prompt builder for layers | 2 hours | Dynamic prompt composition |
| Testing and tuning | 4 hours | Edge cases, topic transitions |
| **Total** | **~15 hours** | Clean, maintainable result |

### Option B: Multi-Agent with Shared State (Enhanced)

| Task | Effort | Notes |
|------|--------|-------|
| Inject full transcript to specialist prompts | 2 hours | Modify `get_specialist_instruction()` |
| Remove `on_enter()` announcements | 0.5 hours | Replace with continuity markers |
| Add conversation context injection | 3 hours | Where in convo, what was said |
| Tune prompts for continuity | 4 hours | "Continue naturally" instructions |
| Handle long transcripts | 2 hours | Summarization for context limits |
| Testing and tuning | 5 hours | Handoff edge cases |
| **Total** | **~17 hours** | Still has inherent transition issues |

### Option C: Orchestrator + Specialists

| Task | Effort | Notes |
|------|--------|-------|
| Create orchestrator agent | 3 hours | Complex prompt management |
| Convert specialists to pure functions | 4 hours | Remove LLM, make deterministic |
| Build response synthesis logic | 4 hours | Orchestrator interprets function outputs |
| Handle multi-topic orchestration | 3 hours | Parallel issues, priorities |
| Testing and tuning | 6 hours | Two-stage reasoning is tricky |
| **Total** | **~20 hours** | Rigid, loses specialist nuance |

---

## 7. Migration Path (For Recommended Option A)

### Phase 1: Foundation (Day 1)

1. Create `grace_unified.py` alongside existing `hvac_agent.py`
2. Build unified prompt from existing specialist prompts
3. Create single `GraceAgent` class with all tools

### Phase 2: Tool Conversion (Day 1-2)

1. Convert routing tools from agent-returning to knowledge-returning
2. Add mode tracking to CallData
3. Build layered prompt builder

### Phase 3: Testing (Day 2-3)

1. Test basic flows: greeting → service → closing
2. Test multi-topic: service + billing in one call
3. Test interruptions and topic pivots
4. Compare against current system behavior

### Phase 4: Cutover (Day 3)

1. Rename `hvac_agent.py` → `hvac_agent_legacy.py`
2. Rename `grace_unified.py` → `hvac_agent.py`
3. Monitor production calls
4. Rollback plan: swap files back

---

## 8. Conclusion

The current multi-agent architecture served well for initial development but creates inherent transition friction. The `session.update_agent()` mechanism and `on_enter()` callbacks make truly seamless handoffs impossible without architectural change.

**Recommendation:** Implement **Alternative A (Single Agent with Tool Specialization)** for:
- Zero perceptible handoffs
- Consistent personality
- Full conversation context
- Simpler codebase
- Easier maintenance

The ~15-hour implementation effort is justified by the significant improvement in caller experience and reduced system complexity.

---

## Appendix: LiveKit Agent Constraints

### session.update_agent() Behavior

From LiveKit Agents 1.3.12:
- `update_agent(new_agent)` replaces the current agent
- `on_enter()` is called automatically on the new agent
- Conversation history is NOT automatically transferred
- TTS voice is session-level (shared) ✅

### Context Management

- LLM context is per-agent (resets on swap)
- Must manually inject conversation history
- Transcript in CallData is separate from LLM context

### Implications

The `update_agent()` mechanism is designed for explicit handoffs (e.g., "Let me transfer you to sales"). For invisible handoffs, staying with one agent and using tools for knowledge injection is the cleaner approach.

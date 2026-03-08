# HVAC Grace - Current State Handoff Analysis

**Generated:** 2025-02-02
**Analyst:** Research Subagent

---

## 1. Step-by-Step Handoff Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CALL LIFECYCLE                                        │
└─────────────────────────────────────────────────────────────────────────────┘

  CALLER DIALS IN
        │
        ▼
┌───────────────┐
│  PortalAgent  │  ◄── No call_data passed (init empty)
│  (Triage)     │      Says: "Thanks for calling, this is Grace..."
└───────────────┘
        │
        │  @session.on("user_input_transcribed") triggered
        │  User says >= 5 chars
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│  INTENT DETECTION (detect_intent function)                       │
│  - Keyword matching against INTENT_KEYWORDS dict                 │
│  - Falls back to "general" if no match                          │
└─────────────────────────────────────────────────────────────────┘
        │
        │  has_transferred = True (prevents re-routing)
        │  call_data.switch_department(intent)
        │  asyncio.create_task(perform_transfer(...))
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│  perform_transfer()                                              │
│  1. await asyncio.sleep(1.0)  ◄── DEAD AIR MOMENT                │
│  2. new_agent = SpecialistAgent(call_data, tools=routing_tools)  │
│  3. session.update_agent(new_agent)  ◄── Triggers on_enter()     │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────┐
│  SpecialistAgent  │
│  on_enter()       │ ◄── HARDCODED GREETING SPOKEN HERE
└───────────────────┘
        │
        │  If caller_name exists:
        │    session.say("What's happening with the equipment?")
        │  Else:
        │    session.say("Can I get your name?")  ◄── RE-ASK MOMENT
        │
        ▼
   LLM takes over with specialist prompt
        │
        │  Caller says "that's it" / "I'm done"
        │  LLM calls route_to_closing()
        │
        ▼
┌───────────────────┐
│  ClosingAgent     │
│  on_enter()       │ ◄── Hardcoded recap speech
└───────────────────┘
```

---

## 2. List of Every "Break the Illusion" Moment

### 🔴 CRITICAL BREAKS

| Location | Problem | Code Reference |
|----------|---------|----------------|
| **on_enter() - All Specialists** | Hardcoded non-contextual greeting ignores what caller just said | Lines 624-731 |
| **Portal → Specialist** | 1-second dead air during transfer | Line 1083 |
| **ServiceAgent.on_enter()** | "Can I get your name?" even though caller may have just introduced themselves to Portal | Line 629 |
| **BillingAgent prompt** | Says "I can help with that" - doesn't know what "that" is | prompts/billing.py |
| **PartsAgent prompt** | Says "I can help with that" - generic, not contextual | prompts/parts.py |
| **Transcript NOT in LLM context** | LLM doesn't see what caller said before transfer | Specialist init doesn't include transcript |

### 🟡 MEDIUM BREAKS

| Location | Problem | Code Reference |
|----------|---------|----------------|
| **Closing recap** | Generic phrases like "your billing question" instead of actual issue | Lines 748-770 |
| **No conversation history passed** | New agent starts fresh, doesn't know prior context | session.update_agent() clears context |
| **Specialist opening lines vary** | Some say "Can I get your name?", others say "I can help with that" | Inconsistent across prompts |

### 🟢 MINOR BREAKS

| Location | Problem | Code Reference |
|----------|---------|----------------|
| **TTS filter catching routing language** | Grace still attempts to say "I've routed your request" | Log: TTS_FILTER catching phrases |
| **"Is there anything else?" phrasing** | Some prompts say "Is there anything else I can help with?" vs "anything else you need?" | Various prompts |

---

## 3. Context Passed vs Lost During Handoff

### ✅ WHAT IS PASSED (via CallData)

```python
@dataclass
class CallData:
    # Call identification
    room_name: str                    ✓ Passed
    call_start: datetime              ✓ Passed
    
    # Caller info (extracted from speech)
    caller_name: str                  ✓ Passed (if extracted)
    caller_phone: str                 ✓ Passed (if extracted)
    caller_company: str               ✓ Passed (if extracted)
    caller_site: str                  ✓ Passed (if extracted)
    caller_role: str                  ✓ Passed (never populated)
    
    # Transcript
    transcript_lines: List[str]       ✓ Captured but NOT used by LLM
    
    # Department tracking
    current_department: str           ✓ Passed
    departments_visited: List[str]    ✓ Passed
```

### ❌ WHAT IS LOST

| Lost Context | Impact |
|--------------|--------|
| **Conversation history** | New LLM starts with blank slate; doesn't know what was discussed |
| **What the caller just said** | Specialist doesn't know the specific request |
| **Portal's response** | No awareness of what Grace (Portal) said to caller |
| **Emotional tone** | Caller frustration/urgency not conveyed |
| **Specific equipment/issue details** | Even if mentioned, not passed to specialist prompt |

### How Context IS Injected (Partial)

```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    # Gets base specialist prompt
    base = base_instructions.get(intent, OFFICE_INSTRUCTION)
    
    # Adds caller context IF collected
    caller_context = call_data.get_caller_context()
    if caller_context != "No caller info collected yet.":
        context_section = f"""
# KNOWN CALLER INFORMATION
The following information has already been collected. DO NOT ask for this again.
{caller_context}

Use this information to personalize your greeting...
"""
        base = base + context_section
    
    return base + CLOSING_SEQUENCE
```

**Problem:** Only caller_name, caller_phone, caller_company, caller_site are injected.
**The actual ISSUE they called about is NOT passed.**

---

## 4. Personality Consistency Analysis

### All Prompts Identify as "Grace" ✓

| Agent | Identity Statement |
|-------|-------------------|
| Portal | "You are Grace, answering the phone for {COMPANY_NAME}" |
| Service | "You are Grace, the service coordinator for {COMPANY_NAME}" |
| Billing | "You are Grace, handling billing inquiries for {COMPANY_NAME}" |
| Parts | "You are Grace, handling parts inquiries for {COMPANY_NAME}" |
| Projects | "You are Grace" (implied) |
| Maintenance | "You are Grace, handling maintenance inquiries for {COMPANY_NAME}" |
| Controls | "You are Grace" (implied) |
| General | "You are Grace, handling general inquiries for {COMPANY_NAME}" |
| Closing | "You are Grace, wrapping up a call for {COMPANY_NAME}" |

### Personality Descriptions DIFFER

| Agent | Personality Description |
|-------|------------------------|
| Portal | None specified |
| Billing | "professional and patient" |
| Parts | "helpful and understanding" |
| General | "friendly and professional" |
| Maintenance | None specified |
| Service | None specified |

### Opening Line INCONSISTENCIES

| Agent | Hardcoded on_enter() | Prompt "YOUR OPENING" |
|-------|---------------------|----------------------|
| Service | "Can I get your name?" or "What's happening with the equipment?" | Different in prompt |
| Billing | "Can I get your name?" | "I can help with that. What's your name and a callback number?" |
| Parts | "Can I get your name?" | "I can help with that. What's your name and a callback number?" |
| General | "Can I get your name?" | "I can help with that. What's your name and a callback number?" |

**PROBLEM:** The hardcoded `on_enter()` says one thing, but the prompt tells the LLM to say something different. The caller hears the hardcoded version, then the LLM might say something different.

---

## 5. Specific Code Locations That Cause Problems

### Problem 1: Hardcoded on_enter() Greetings
**File:** `hvac_agent.py`
**Lines:** 624-731

```python
async def on_enter(self) -> None:
    caller_name = self._call_data.caller_name if self._call_data else None
    if caller_name:
        self.session.say("What's happening with the equipment?", allow_interruptions=True)
    else:
        self.session.say("Can I get your name?", allow_interruptions=True)
```

**Issue:** Generic greeting ignores the conversation context. Caller just explained their issue to Portal, and now they're asked again.

---

### Problem 2: Dead Air During Transfer
**File:** `hvac_agent.py`
**Line:** 1083

```python
await asyncio.sleep(1.0)
```

**Issue:** 1-second silence during handoff. Caller wonders if they've been disconnected.

---

### Problem 3: Transcript Not Included in LLM Context
**File:** `hvac_agent.py`
**Lines:** 282-310

```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    # Only includes caller_context (name, phone, company, site)
    # Does NOT include transcript_lines
```

**Issue:** The LLM doesn't know what the caller said. It's flying blind.

---

### Problem 4: Prompt Opening vs Hardcoded Mismatch
**File:** `prompts/billing.py` (and others)

```python
# YOUR OPENING (say this immediately when you connect)
"I can help with that. What's your name and a callback number?"
```

**vs** `hvac_agent.py` line 661:
```python
self.session.say("Which invoice can I help you with?", allow_interruptions=True)
```

**Issue:** The hardcoded message plays, THEN the LLM might try to say its programmed opening, creating double-speak or confusion.

---

### Problem 5: Portal LLM Still Generating Routing Language
**Evidence from logs:**
```
TTS_FILTER: 'I've routed your request for a certificate of insu' -> '[empty]
```

**Issue:** Despite the prompt saying not to announce transfers, the LLM still generates this text. The TTS filter catches it, but there's a moment where nothing is said (filtered to empty), creating silence.

---

### Problem 6: Agent Map Doesn't Include Portal
**File:** `hvac_agent.py`
**Lines:** 1069-1078

```python
agent_map = {
    "service": ServiceAgent,
    "parts": PartsAgent,
    # ... etc
    # NO PortalAgent - can't route back
}
```

**Issue:** If someone calls and then asks about something completely different, there's no way to go back to triage.

---

## 6. Summary: The Fundamental Issue

The current architecture treats each specialist as a **separate LLM session** that starts from scratch. The only continuity is:

1. Extracted caller info (name, phone, etc.) - appended to system prompt
2. Department tracking (for recap at closing)

**What's missing:**

1. **The actual conversation** - What did the caller say? What did Portal say?
2. **The reason for transfer** - Why did we route to this specialist?
3. **Continuous personality** - Grace should feel like one person, not a handoff to a "specialist"
4. **Seamless transition** - No dead air, no re-introductions, no re-asking

The TTS filter is a band-aid for routing language, but the fundamental problem is that **each agent transition breaks the conversational thread**.

---

## 7. Recommendations for "One Grace" Architecture

1. **Include transcript in specialist prompt** - The new agent should know what was said
2. **Remove hardcoded on_enter() speeches** - Let the LLM respond contextually
3. **Add transfer reason to context** - "Caller needs help with [service request for broken AC at City Hall]"
4. **Eliminate dead air** - Start new agent before stopping old one, or fill with bridging phrase
5. **Unify personality descriptions** - All prompts should describe the same Grace
6. **Consider single-agent architecture** - One LLM with tools for different departments instead of separate agents

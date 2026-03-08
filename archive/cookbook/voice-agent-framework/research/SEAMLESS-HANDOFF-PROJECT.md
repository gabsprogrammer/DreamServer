# Project: Seamless Grace Handoffs

## Vision
Callers interact with ONE person—Grace—throughout their entire call, never experiencing transfers, repetition, or personality shifts, regardless of how many topics they discuss.

---

## Current State Summary

### Critical Problems Identified

**1. Conversation Context Lost on Handoff**
- When `session.update_agent()` swaps agents, the LLM context resets
- New specialist only sees extracted fields (name, phone), not what was discussed
- Callers are asked to repeat information they just provided

**2. Hardcoded `on_enter()` Greetings**
- Each specialist says a scripted phrase ("Can I get your name?" or "I can help with that")
- Creates jarring seams—caller hears "new person" picking up
- Location: `hvac_agent.py` lines 624-731

**3. Dead Air During Transfer**
- `await asyncio.sleep(1.0)` creates 1-second silence
- Location: `hvac_agent.py` line 1083

**4. Personality Inconsistencies**
- Billing prompt: "professional and patient"
- Parts prompt: "helpful and understanding"
- Service prompt: no personality defined
- Different opening lines across specialists

**5. Prompt/Hardcode Mismatch**
- Prompts say "YOUR OPENING: I can help with that..."
- But `on_enter()` says different hardcoded phrases
- Results in double-speak or confusion

**6. TTS Filter Band-Aid**
- LLM still generates routing language ("I've routed your request...")
- TTS filter catches it, but creates silence when filtered to empty

---

## Recommended Architecture

### Choice: Single Agent with Tool Specialization

**Rationale:**
1. **Zero perceptible handoffs** — one agent means one continuous conversation
2. **Full context always available** — no LLM resets between topics
3. **Consistent personality** — single prompt defines Grace once
4. **LiveKit constraint workaround** — `session.update_agent()` inherently triggers `on_enter()`; avoiding it eliminates announcement points
5. **Simpler codebase** — replace 9 agent classes with 1

**How It Works:**
- Single `GraceAgent` handles all calls from greeting to closing
- Routing "tools" inject domain knowledge into the prompt, not swap agents
- Tools return strings (knowledge), not new Agent instances
- CallData tracks active mode, pending topics, and full transcript
- LLM naturally transitions between topics using conversation context

---

## Implementation Phases

### Phase 1: Quick Wins (< 2 hours)
*Immediate improvements without full refactor*

- [ ] **1.1** Remove all `on_enter()` hardcoded greetings
  - File: `hvac_agent.py` lines 624-731
  - Change: Delete or make methods pass-through
  
- [ ] **1.2** Remove 1-second dead air sleep
  - File: `hvac_agent.py` line 1083
  - Change: Delete `await asyncio.sleep(1.0)`
  
- [ ] **1.3** Inject transcript into specialist prompts
  - File: `hvac_agent.py` function `get_specialist_instruction()`
  - Change: Add `call_data.transcript_lines` to prompt context
  
- [ ] **1.4** Unify personality descriptions in all prompts
  - Files: `prompts/*.py`
  - Change: Standardize to "warm, professional, efficient"

### Phase 2: Core Refactor (4-8 hours)
*Single Agent architecture*

- [ ] **2.1** Create unified Grace prompt
  - New file: `prompts/grace_unified.py`
  - Combine core personality + domain knowledge layers
  
- [ ] **2.2** Create single GraceAgent class
  - New file: `grace_agent.py`
  - One agent with all tools, no agent swapping
  
- [ ] **2.3** Convert routing tools to knowledge injectors
  - Change tool returns from `(Agent, "")` to knowledge strings
  - Add dynamic prompt composition
  
- [ ] **2.4** Enhance CallData for single-agent tracking
  - File: `state.py` (or `hvac_agent.py` CallData class)
  - Add: `current_mode`, `active_topics`, `pending_questions`
  
- [ ] **2.5** Create layered prompt builder
  - File: `prompt_builder.py` (enhance existing)
  - Function: `build_grace_prompt(call_data, mode_knowledge)`

### Phase 3: Polish (2-4 hours)
*Fine-tuning and edge cases*

- [ ] **3.1** Multi-topic handling
  - Caller mentions service AND billing in one sentence
  - Grace handles sequentially with smooth transitions
  
- [ ] **3.2** Topic return logic
  - "Now, about that invoice you mentioned earlier..."
  - Track and return to pending topics
  
- [ ] **3.3** Closing recap accuracy
  - Recap should reference specific issues discussed
  - Not generic "your billing question"
  
- [ ] **3.4** Edge case testing
  - Caller explicitly asks for transfer
  - Caller interrupts with urgent topic
  - Call goes beyond context window
  
- [ ] **3.5** Legacy cleanup
  - Archive old agent classes
  - Update tests

---

## Detailed Implementation Specs

### Spec 1: Remove Hardcoded on_enter() Greetings

**File:** `hvac_agent.py`
**Lines:** 624-731 (all `on_enter()` methods in specialist classes)

**Current Code (example from ServiceAgent):**
```python
async def on_enter(self) -> None:
    caller_name = self._call_data.caller_name if self._call_data else None
    if caller_name:
        self.session.say("What's happening with the equipment?", allow_interruptions=True)
    else:
        self.session.say("Can I get your name?", allow_interruptions=True)
```

**Change To:**
```python
async def on_enter(self) -> None:
    # Let LLM handle greeting based on context - no hardcoded speech
    pass
```

**Apply to:** ServiceAgent, BillingAgent, PartsAgent, ProjectsAgent, ControlsAgent, MaintenanceAgent, GeneralAgent

---

### Spec 2: Remove Dead Air Sleep

**File:** `hvac_agent.py`
**Line:** 1083 (inside `perform_transfer()`)

**Current Code:**
```python
async def perform_transfer(session, call_data, intent, tools):
    await asyncio.sleep(1.0)  # DELETE THIS
    new_agent = SpecialistAgent(call_data, tools=tools)
    session.update_agent(new_agent)
```

**Change To:**
```python
async def perform_transfer(session, call_data, intent, tools):
    new_agent = SpecialistAgent(call_data, tools=tools)
    session.update_agent(new_agent)
```

---

### Spec 3: Inject Transcript into Specialist Prompts

**File:** `hvac_agent.py`
**Function:** `get_specialist_instruction()` (approximately lines 282-310)

**Current Code:**
```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    base = base_instructions.get(intent, OFFICE_INSTRUCTION)
    caller_context = call_data.get_caller_context()
    if caller_context != "No caller info collected yet.":
        context_section = f"""
# KNOWN CALLER INFORMATION
{caller_context}
"""
        base = base + context_section
    return base + CLOSING_SEQUENCE
```

**Change To:**
```python
def get_specialist_instruction(intent: str, call_data: CallData) -> str:
    base = base_instructions.get(intent, OFFICE_INSTRUCTION)
    
    # Add caller context
    caller_context = call_data.get_caller_context()
    if caller_context != "No caller info collected yet.":
        context_section = f"""
# KNOWN CALLER INFORMATION (DO NOT RE-ASK)
{caller_context}
"""
        base = base + context_section
    
    # ADD: Full transcript context
    if call_data.transcript_lines:
        transcript = "\n".join(call_data.transcript_lines[-20:])  # Last 20 lines
        transcript_section = f"""
# CONVERSATION SO FAR
Continue naturally from this conversation. DO NOT re-introduce yourself.
DO NOT re-ask for information already provided.

{transcript}

# IMPORTANT
The caller just spoke to you (Grace). Continue the same conversation seamlessly.
"""
        base = base + transcript_section
    
    return base + CLOSING_SEQUENCE
```

---

### Spec 4: Create Unified Grace Prompt

**New File:** `prompts/grace_unified.py`

```python
GRACE_CORE_PERSONALITY = """You are Grace, answering the phone for {company_name}, a commercial HVAC contractor.

# WHO YOU ARE
You're warm, professional, and efficient. Callers have real problems and value their time.
You acknowledge what they say, gather what you need, and ensure the right people follow up.

You are ONE person throughout the entire call. If someone mentions their AC is down AND asks about 
an invoice, you help with BOTH. You never say "let me transfer you" or act like different topics 
are handled by different people. It's all you.

# HOW YOU SPEAK
- One question at a time. Ask, wait for the answer, then continue.
- Use natural contractions: "I'll," "you're," "what's," "we'll"
- Confirm what you heard: "A rooftop unit making a grinding noise, got it."
- Brief acknowledgments: "Got it." "I see." "Okay."
- Read back numbers: "That's 5-5-5, 1-2-3-4?"

# WHAT YOU NEVER DO
- Ask multiple questions at once
- Re-ask for information the caller already gave you
- Announce transfers, departments, or routing
- Use words like "agent," "specialist," "system," "routing," "ticket"
- Promise specific prices, arrival times, or availability
- Say "let me transfer you" or "connecting you to"

# TIME CONTEXT
Current: {current_time}
Business hours: 7 AM - 5 PM weekdays
"""

# Domain knowledge modules (injected based on active topic)
SERVICE_KNOWLEDGE = """
# CURRENT FOCUS: Equipment Service
Required: site, issue description, urgency, callback contact
- Business hours: Get tech out ASAP
- After hours emergency: On-call tech calls back within 30-60 min
- After hours non-emergency: First thing tomorrow
- Never promise specific arrival times
"""

BILLING_KNOWLEDGE = """
# CURRENT FOCUS: Billing Inquiry
Required: company name, invoice number (or site/date), nature of inquiry
- Cannot access account balances or payment history
- Cannot accept payments or promise credits
- Accounting calls back within one business day
- Read back invoice numbers for accuracy
"""

PARTS_KNOWLEDGE = """
# CURRENT FOCUS: Parts Inquiry
Required: ticket number (or site), part description, wait time so far
- Cannot promise delivery dates
- Cannot guarantee availability
- Parts coordinator calls back within a few hours
"""

# ... similar for maintenance, projects, controls, general

def build_grace_prompt(call_data, mode_knowledge=""):
    """Build complete Grace prompt with all context layers."""
    from datetime import datetime
    
    prompt = GRACE_CORE_PERSONALITY.format(
        company_name="Light Heart Mechanical",
        current_time=datetime.now().strftime("%A, %B %d at %I:%M %p")
    )
    
    # Layer 2: Caller context
    if call_data.caller_name or call_data.caller_phone:
        prompt += f"""
# CALLER INFO (already collected - DO NOT re-ask)
- Name: {call_data.caller_name or 'Not yet collected'}
- Phone: {call_data.caller_phone or 'Not yet collected'}
- Company: {call_data.caller_company or 'Not yet collected'}
- Site: {call_data.caller_site or 'Not yet collected'}
"""
    
    # Layer 3: Mode-specific knowledge
    if mode_knowledge:
        prompt += f"""
{mode_knowledge}
"""
    
    # Layer 4: Transcript (last 15 exchanges)
    if call_data.transcript_lines:
        recent = "\n".join(call_data.transcript_lines[-30:])
        prompt += f"""
# CONVERSATION SO FAR
{recent}

Continue naturally from this point.
"""
    
    # Layer 5: Pending topics
    if hasattr(call_data, 'pending_topics') and call_data.pending_topics:
        prompt += f"""
# PENDING TOPICS (mention before closing)
{chr(10).join('- ' + t for t in call_data.pending_topics)}
When current topic is complete, transition with: "Now, about that [topic] you mentioned..."
"""
    
    return prompt
```

---

### Spec 5: Create Single GraceAgent Class

**New File:** `grace_agent.py`

```python
from livekit.agents import Agent, function_tool
from prompts.grace_unified import build_grace_prompt, SERVICE_KNOWLEDGE, BILLING_KNOWLEDGE, PARTS_KNOWLEDGE

class GraceAgent(Agent):
    """Single unified Grace agent - handles all topics without handoffs."""
    
    def __init__(self, call_data, tools=None):
        self._call_data = call_data
        self._current_mode = "general"
        self._mode_knowledge = ""
        
        # Build initial prompt
        initial_prompt = build_grace_prompt(call_data)
        
        super().__init__(
            instructions=initial_prompt,
            tools=tools or self._get_all_tools()
        )
    
    def _get_all_tools(self):
        return [
            self.activate_service_mode,
            self.activate_billing_mode,
            self.activate_parts_mode,
            self.activate_maintenance_mode,
            self.activate_projects_mode,
            self.activate_controls_mode,
            self.create_ticket,
            self.route_to_closing,
            # ... other action tools
        ]
    
    @function_tool()
    async def activate_service_mode(self, issue_summary: str, urgency: str) -> str:
        """Activate when caller has equipment issues. Returns guidance, not a transfer."""
        self._call_data.switch_department("service")
        self._current_mode = "service"
        self._mode_knowledge = SERVICE_KNOWLEDGE
        return f"""Service mode active. Issue: {issue_summary}. Urgency: {urgency}.
Collect: site, callback contact, after-hours confirmation if applicable.
{SERVICE_KNOWLEDGE}"""
    
    @function_tool()
    async def activate_billing_mode(self, inquiry_type: str) -> str:
        """Activate when caller has billing questions. Returns guidance, not a transfer."""
        self._call_data.switch_department("billing")
        self._current_mode = "billing"
        self._mode_knowledge = BILLING_KNOWLEDGE
        return f"""Billing mode active. Inquiry type: {inquiry_type}.
Collect: company, invoice number, nature of inquiry.
{BILLING_KNOWLEDGE}"""
    
    @function_tool()
    async def activate_parts_mode(self, part_context: str) -> str:
        """Activate when caller asking about parts status. Returns guidance, not a transfer."""
        self._call_data.switch_department("parts")
        self._current_mode = "parts"
        self._mode_knowledge = PARTS_KNOWLEDGE
        return f"""Parts mode active. Context: {part_context}.
Collect: ticket number, part description, wait time.
{PARTS_KNOWLEDGE}"""
    
    # Similar methods for maintenance, projects, controls...
    
    @function_tool()
    async def create_ticket(self, department: str, details: dict) -> str:
        """Create a ticket once all required info is collected."""
        # Implementation for ticket creation
        return f"Ticket created for {department}. Confirmation pending."
    
    @function_tool()
    async def route_to_closing(self) -> str:
        """When caller says they're done, transition to closing."""
        topics = self._call_data.departments_visited
        return f"""Caller is done. Summarize what was handled:
Topics discussed: {', '.join(topics)}
Give brief recap and say goodbye warmly."""
```

---

### Spec 6: Enhance CallData for Topic Tracking

**File:** `state.py` (or in `hvac_agent.py` where CallData is defined)

**Add these fields:**

```python
@dataclass
class CallData:
    # Existing fields...
    room_name: str = ""
    call_start: datetime = field(default_factory=datetime.now)
    caller_name: str = ""
    caller_phone: str = ""
    caller_company: str = ""
    caller_site: str = ""
    transcript_lines: List[str] = field(default_factory=list)
    current_department: str = "portal"
    departments_visited: List[str] = field(default_factory=list)
    
    # NEW FIELDS FOR SINGLE-AGENT TRACKING
    current_mode: str = "general"  # service | billing | parts | etc.
    active_topics: List[str] = field(default_factory=list)  # Issues being discussed now
    pending_topics: List[str] = field(default_factory=list)  # Mentioned but not yet addressed
    pending_questions: List[str] = field(default_factory=list)  # Info still needed
    urgency_level: str = "normal"  # normal | urgent | emergency
    
    def add_topic(self, topic: str, pending: bool = False):
        """Add a topic to active or pending list."""
        if pending:
            if topic not in self.pending_topics:
                self.pending_topics.append(topic)
        else:
            if topic not in self.active_topics:
                self.active_topics.append(topic)
            # Remove from pending if it was there
            if topic in self.pending_topics:
                self.pending_topics.remove(topic)
    
    def complete_topic(self, topic: str):
        """Mark a topic as complete."""
        if topic in self.active_topics:
            self.active_topics.remove(topic)
        if topic not in self.departments_visited:
            self.departments_visited.append(topic)
```

---

## Success Metrics

- [ ] **Caller never hears "let me transfer you"** or similar routing language
- [ ] **Caller never asked to repeat information** they already provided
- [ ] **Grace's personality is consistent** throughout the call (warm, efficient)
- [ ] **Topic shifts feel natural** ("Now, about that invoice...")
- [ ] **Multi-issue calls handled without bouncing** (service + billing in one call)
- [ ] **No dead air** during topic transitions
- [ ] **Accurate closing recap** referencing actual issues discussed

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Larger unified prompt exceeds token limit | Low | High | Keep domain layers modular; only inject active domain |
| LLM confused about which mode is active | Medium | Medium | Clear "CURRENT FOCUS" headers; explicit mode state |
| Regression in specialist quality | Medium | Medium | Keep domain knowledge detailed; thorough testing |
| Transition phrasing sounds robotic | Low | Medium | Test with sample calls; tune prompt language |
| Long calls exceed context window | Low | High | Summarize old transcript; keep last N exchanges |

---

## Estimated Total Effort

| Phase | Time Estimate | Dependencies |
|-------|---------------|--------------|
| Phase 1: Quick Wins | 1.5 - 2 hours | None |
| Phase 2: Core Refactor | 4 - 8 hours | Phase 1 complete |
| Phase 3: Polish | 2 - 4 hours | Phase 2 complete |
| **Total** | **7.5 - 14 hours** | |

**Recommended approach:** 
- Implement Phase 1 immediately (low risk, immediate benefit)
- Phase 2 can be done in a single focused session
- Phase 3 can be iterative based on testing feedback

---

## Files to Modify/Create

### Modified Files
- `hvac_agent.py` - Remove hardcoded greetings, dead air, inject transcript
- `state.py` or CallData class - Add topic tracking fields
- `prompt_builder.py` - Enhance for layered prompts
- `prompts/*.py` - Unify personality descriptions

### New Files  
- `prompts/grace_unified.py` - Unified prompt with domain layers
- `grace_agent.py` - Single GraceAgent class (Phase 2)

### Archived/Deprecated (after Phase 2)
- Individual specialist agent classes (ServiceAgent, BillingAgent, etc.)
- Per-specialist prompts (can be kept for reference, but not used)

---

*Project Plan Generated: February 2, 2026*
*Based on research by: Current State Analyst, Architecture Researcher, Prompt Engineering Researcher*

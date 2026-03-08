"""
HVAC Grace - Intent Detection
Detects department routing and caller intents from speech.

Compatible with both V4 test framework and multi-agent system.
Maps intent names to match multi-agent routing (e.g., "general" -> "office").
"""

import re
from typing import Optional, Tuple
from state import CallState


# Department detection keywords - aligned with multi-agent specialist names
DEPARTMENT_KEYWORDS = {
    "service": [
        "service", "repair", "broken", "not working", "stopped working",
        "emergency", "no heat", "no cooling", "no ac", "no air",
        "leaking", "noise", "loud", "smell", "smoke", "frozen",
        "won't turn on", "won't start", "tripped", "down", "offline",
        "making noise", "not running", "running constantly", "cooler", "freezer", "temperature", "not holding", "problem", "issue", "trouble", "help", "need service"
    ],
    "billing": [
        "billing", "invoice", "bill", "payment", "pay", "charge",
        "statement", "account", "balance", "credit", "refund",
        "dispute", "overcharge", "pricing", "cost"
    ],
    "parts": [
        "part", "parts", "filter", "filters", "belt", "motor",
        "compressor", "coil", "thermostat", "order", "ordering",
        "pickup", "pick up", "availability"
    ],
    "projects": [
        "project", "quote", "estimate", "install", "installation",
        "replace", "replacement", "new unit", "new system", "upgrade",
        "addition", "construction", "retrofit", "bid"
    ],
    "maintenance": [
        "maintenance", "pm", "preventive", "contract", "agreement",
        "scheduled", "routine", "inspection", "tune-up", "tune up"
    ],
    "controls": [
        "controls", "bas", "building automation", "bms", "ddc",
        "niagara", "tridium", "trane tracer", "metasys", "jci",
        "johnson", "honeywell", "alerton", "bacnet", "sensor",
        "setpoint", "schedule", "programming", "alarm", "trend"
    ],
    # "general" maps to "office" specialist in multi-agent system
    "office": [
        "general", "question", "help", "information", "speak to someone",
        "talk to someone", "representative", "operator"
    ]
}

# Intent detection patterns
CLOSING_PATTERNS = [
    r"that'?s (all|it|everything)",
    r"nothing else",
    r"i'?m (good|done|all set)",
    r"no,? (thanks|thank you)",
    r"that covers it",
    r"we'?re (good|done|all set)",
    r"i think that'?s (it|all)",
    r"goodbye",
    r"bye",
    r"have a (good|great|nice)",
    r"talk to you later"
]

TICKET_STATUS_PATTERNS = [
    r"status (of|on) (my|the|our) ticket",
    r"check (on|my) ticket",
    r"what'?s happening with (my|the|our)",
    r"any update",
    r"have you heard anything",
    r"when (will|is) (someone|a tech|the technician)",
    r"where is (my|the) tech",
    r"ticket (?:number )?(\d+)"
]

TICKET_UPDATE_PATTERNS = [
    r"(change|update) (the|my) (address|phone|contact)",
    r"different (address|phone|number)",
    r"actually.*(address|phone|number) (is|should be)",
    r"wrong (address|phone)",
    r"correct (address|phone) is"
]

TICKET_CANCEL_PATTERNS = [
    r"cancel (the|my|that) ticket",
    r"don'?t need (the|that|a) (tech|technician|service)",
    r"fixed it (myself|ourselves)",
    r"resolved (itself|the issue)",
    r"no longer need",
    r"disregard (the|my|that)"
]

EMERGENCY_PATTERNS = [
    r"emergency",
    r"urgent",
    r"(have to|need to|must) close",
    r"can'?t (open|operate)",
    r"safety (issue|hazard|concern)",
    r"gas (smell|leak)",
    r"smoke",
    r"(water|refrigerant) (leak|leaking)",
    r"(flood|flooding)",
    r"(food|medicine|server|data).*(spoil|damage|risk)"
]


def detect_department(text: str) -> Optional[str]:
    """
    Detect which department the caller needs based on keywords.
    Returns department name or None if unclear.

    Note: Returns department names matching multi-agent specialist classes.
    """
    text_lower = text.lower()

    # Score each department
    scores = {}
    for dept, keywords in DEPARTMENT_KEYWORDS.items():
        score = 0
        for keyword in keywords:
            if keyword in text_lower:
                # Longer matches are weighted more
                score += len(keyword)
        if score > 0:
            scores[dept] = score

    if not scores:
        return None

    # Return highest scoring department
    return max(scores, key=scores.get)


def should_switch_department(detected: Optional[str], state: CallState, text: str) -> bool:
    """
    Determine if we should switch to a different department.
    Considers context to avoid spurious switches.
    """
    if not detected:
        return False

    # Already in this department
    if detected == state.department:
        return False

    # Check if this is clearly about something new
    new_topic_signals = [
        "also", "another thing", "one more thing", "separately",
        "different issue", "other question", "while i have you",
        "actually", "i also need"
    ]

    text_lower = text.lower()

    # Strong department keywords should always trigger
    strong_keywords = {
        "service": ["broken", "not working", "emergency", "repair"],
        "billing": ["invoice", "payment", "bill"],
        "parts": ["order a part", "need a filter"],
        "projects": ["quote", "estimate", "install"],
        "maintenance": ["contract", "pm program"],
        "controls": ["bas", "building automation", "niagara"]
    }

    for keyword in strong_keywords.get(detected, []):
        if keyword in text_lower:
            return True

    # Check for new topic signals
    for signal in new_topic_signals:
        if signal in text_lower:
            return True

    # If current ticket is complete, more willing to switch
    from state import is_ticket_complete
    if is_ticket_complete(state):
        return True

    # Default: don't switch mid-conversation unless clear signal
    return False


def detect_closing_intent(text: str) -> bool:
    """Detect if caller is indicating they're done."""
    text_lower = text.lower()

    for pattern in CLOSING_PATTERNS:
        if re.search(pattern, text_lower):
            return True

    return False


def detect_ticket_status_request(text: str) -> Optional[int]:
    """
    Detect if caller is asking about ticket status.
    Returns ticket ID if mentioned, or -1 if general status request.
    """
    text_lower = text.lower()

    for pattern in TICKET_STATUS_PATTERNS:
        match = re.search(pattern, text_lower)
        if match:
            # Check if ticket number was mentioned
            groups = match.groups()
            for g in groups:
                if g and g.isdigit():
                    return int(g)
            return -1  # Status request but no specific ticket

    return None


def detect_ticket_update_request(text: str) -> Optional[str]:
    """
    Detect if caller wants to update ticket info.
    Returns the field they want to update.
    """
    text_lower = text.lower()

    for pattern in TICKET_UPDATE_PATTERNS:
        match = re.search(pattern, text_lower)
        if match:
            # Try to determine which field
            if "address" in text_lower:
                return "site_address"
            elif "phone" in text_lower or "number" in text_lower:
                return "site_contact_phone"
            elif "contact" in text_lower:
                return "site_contact_name"
            return "unknown"

    return None


def detect_ticket_cancel_request(text: str) -> bool:
    """Detect if caller wants to cancel a ticket."""
    text_lower = text.lower()

    for pattern in TICKET_CANCEL_PATTERNS:
        if re.search(pattern, text_lower):
            return True

    return False


def detect_emergency(text: str) -> bool:
    """Detect if this is an emergency situation."""
    text_lower = text.lower()

    for pattern in EMERGENCY_PATTERNS:
        if re.search(pattern, text_lower):
            return True

    return False


def detect_ticket_action(text: str, open_tickets: list) -> Optional[dict]:
    """
    Detect if caller wants to perform an action on an existing ticket.
    Returns action dict if detected.
    """
    # Check for status request
    ticket_id = detect_ticket_status_request(text)
    if ticket_id is not None:
        if ticket_id == -1 and open_tickets:
            # Use most recent open ticket
            ticket_id = open_tickets[0].get("id")
        if ticket_id:
            return {"action": "status_check", "ticket_id": ticket_id}

    # Check for cancel request
    if detect_ticket_cancel_request(text):
        if open_tickets:
            # Assume most recent unless specified
            return {"action": "cancel", "ticket_id": open_tickets[0].get("id")}

    # Check for update request
    field = detect_ticket_update_request(text)
    if field:
        if open_tickets:
            return {"action": "update", "ticket_id": open_tickets[0].get("id"), "field": field}

    return None


# Alias for V4 test framework compatibility
def detect_intent(text: str) -> Optional[str]:
    """Alias for detect_department for V4 compatibility."""
    return detect_department(text)

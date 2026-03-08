"""
HVAC Grace - Information Extraction
Extracts caller info and ticket details from conversation.

Compatible with both V4 test framework and multi-agent system.
"""

import re
from typing import Optional, Tuple
from state import CallState


# Phone number patterns
PHONE_PATTERNS = [
    r'\b(\d{3}[-.\s]?\d{3}[-.\s]?\d{4})\b',  # 555-123-4567
    r'\b(\(\d{3}\)\s?\d{3}[-.\s]?\d{4})\b',   # (555) 123-4567
    r'\b(\d{10})\b',                            # 5551234567
]

# Name patterns - looking for "my name is X" or "this is X" or "I'm X"
NAME_PATTERNS = [
    r"(?:my name is|i'm|i am|this is|it's)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)",
    r"(?:name'?s?)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)",
]

# Company patterns
COMPANY_PATTERNS = [
    r"(?:from|with|at|work for|calling from)\s+([A-Z][A-Za-z\s&']+?)(?:\s+(?:and|about|regarding|on|at)|[,.]|$)",
    r"(?:company is|company name is)\s+([A-Z][A-Za-z\s&']+?)(?:\s+(?:and|about|regarding)|[,.]|$)",
]

# Site/Address patterns
ADDRESS_PATTERNS = [
    r'(\d+\s+[A-Z][A-Za-z\s]+(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Lane|Ln|Way|Place|Pl|Court|Ct))',
    r'(\d+\s+[A-Z][A-Za-z]+\s+(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Lane|Ln|Way|Place|Pl|Court|Ct))',
]

# Equipment type patterns
EQUIPMENT_PATTERNS = [
    r'(rooftop\s+unit|RTU|split\s+system|chiller|boiler|air\s+handler|AHU|VAV|fan\s+coil|mini\s+split|package\s+unit|heat\s+pump|furnace|cooling\s+tower)',
    r'(Carrier|Trane|Lennox|York|Daikin|Rheem|Mitsubishi|LG)',
]

# Urgency patterns
URGENCY_PATTERNS = {
    "emergency": [
        r"emergency", r"urgent", r"can't (open|operate)", r"safety",
        r"gas (smell|leak)", r"smoke", r"flooding", r"data center",
        r"(food|medicine|server).*(spoil|damage|risk)", r"critical"
    ],
    "urgent": [
        r"as soon as possible", r"asap", r"today if possible",
        r"really need", r"very uncomfortable", r"business impact"
    ]
}


def extract_phone(text: str) -> Optional[str]:
    """Extract phone number from text."""
    for pattern in PHONE_PATTERNS:
        match = re.search(pattern, text)
        if match:
            phone = match.group(1)
            # Normalize: remove non-digits
            digits = re.sub(r'\D', '', phone)
            if len(digits) == 10:
                return f"{digits[:3]}-{digits[3:6]}-{digits[6:]}"
            elif len(digits) == 11 and digits[0] == '1':
                return f"{digits[1:4]}-{digits[4:7]}-{digits[7:]}"
    return None


def extract_name(text: str) -> Optional[str]:
    """Extract caller name from text."""
    for pattern in NAME_PATTERNS:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            name = match.group(1).strip()
            # Basic validation - at least 2 characters, starts with letter
            if len(name) >= 2 and name[0].isalpha():
                return name.title()
    return None


def extract_company(text: str) -> Optional[str]:
    """Extract company name from text."""
    for pattern in COMPANY_PATTERNS:
        match = re.search(pattern, text)
        if match:
            company = match.group(1).strip()
            # Clean up
            company = re.sub(r'\s+', ' ', company)
            if len(company) >= 2:
                return company
    return None


def extract_address(text: str) -> Optional[str]:
    """Extract street address from text."""
    for pattern in ADDRESS_PATTERNS:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return None


def extract_equipment(text: str) -> Optional[str]:
    """Extract equipment type from text."""
    text_lower = text.lower()
    for pattern in EQUIPMENT_PATTERNS:
        match = re.search(pattern, text_lower, re.IGNORECASE)
        if match:
            return match.group(1)
    return None


def detect_urgency(text: str) -> str:
    """Detect urgency level from text."""
    text_lower = text.lower()

    for level, patterns in URGENCY_PATTERNS.items():
        for pattern in patterns:
            if re.search(pattern, text_lower):
                return level

    return "normal"


def extract_caller_info(text: str, state: CallState) -> bool:
    """
    Extract caller info from text and update state.
    Returns True if any new info was extracted.
    """
    updated = False

    # Extract phone if not already set
    if not state.caller_phone:
        phone = extract_phone(text)
        if phone:
            state.caller_phone = phone
            updated = True
            print(f"[EXTRACTED] Phone: {phone}")

    # Extract name if not already set
    if not state.caller_name:
        name = extract_name(text)
        if name:
            state.caller_name = name
            updated = True
            print(f"[EXTRACTED] Name: {name}")

    # Extract company if not already set
    if not state.caller_company:
        company = extract_company(text)
        if company:
            state.caller_company = company
            updated = True
            print(f"[EXTRACTED] Company: {company}")

    return updated


def extract_ticket_fields(text: str, state: CallState) -> bool:
    """
    Extract ticket-specific fields from text and update current ticket.
    Returns True if any new info was extracted.
    """
    updated = False
    current_ticket = state.tickets_in_progress.get(state.department, {})

    # Extract address/site
    if not current_ticket.get("site") and not current_ticket.get("address"):
        address = extract_address(text)
        if address:
            state.set_ticket_field("address", address)
            updated = True
            print(f"[EXTRACTED] Address: {address}")

    # Look for site name in quotes or after "at" or "for"
    site_match = re.search(r'(?:at|for|called|named)\s+(?:the\s+)?([A-Z][A-Za-z\s]+?)(?:\s+(?:on|at|building)|[,.]|$)', text)
    if site_match and not current_ticket.get("site"):
        site = site_match.group(1).strip()
        if len(site) >= 3 and site.lower() not in ["the", "our", "my"]:
            state.set_ticket_field("site", site)
            updated = True
            print(f"[EXTRACTED] Site: {site}")

    # Extract equipment type
    if not current_ticket.get("equipment"):
        equipment = extract_equipment(text)
        if equipment:
            state.set_ticket_field("equipment", equipment)
            updated = True
            print(f"[EXTRACTED] Equipment: {equipment}")

    # Detect urgency
    urgency = detect_urgency(text)
    if urgency != "normal" and current_ticket.get("urgency") != "emergency":
        state.set_ticket_field("urgency", urgency)
        updated = True
        print(f"[EXTRACTED] Urgency: {urgency}")

    # Extract issue description (longer text segments)
    if not current_ticket.get("issue") and len(text) > 20:
        # Look for problem descriptions
        issue_patterns = [
            r"(?:problem is|issue is|it's|they're)\s+(.{10,100})",
            r"(?:not|isn't|won't|can't)\s+(.{5,50})",
        ]
        for pattern in issue_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                issue = match.group(1).strip()
                state.set_ticket_field("issue", issue[:200])  # Limit length
                updated = True
                print(f"[EXTRACTED] Issue: {issue[:50]}...")
                break

    return updated


def extract_invoice_number(text: str) -> Optional[str]:
    """Extract invoice number from text."""
    patterns = [
        r'invoice\s*(?:#|number|num)?\s*(\d{4,10})',
        r'(?:#|number|num)\s*(\d{4,10})',
        r'\b(\d{5,10})\b',  # Any 5-10 digit number as fallback
    ]

    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1)

    return None

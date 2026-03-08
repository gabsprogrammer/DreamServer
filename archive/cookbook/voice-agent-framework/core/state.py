"""
HVAC Grace - Call State Compatibility Layer
Maps between V4 test framework expectations (CallState) and current multi-agent system (CallData).

This module provides the CallState interface that V4 tests expect while being compatible
with the current multi-agent architecture.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional
import json


@dataclass
class CallState:
    """
    Complete state for a single call - compatible with both V4 test framework and multi-agent system.

    The V4 test framework uses this class directly. The multi-agent system uses CallData,
    but this provides the same interface for testing purposes.
    """

    # Call identification
    call_id: str = ""
    call_start: datetime = field(default_factory=datetime.now)

    # Phase tracking (maps to multi-agent routing)
    phase: str = "greeting"  # greeting | intake | closing
    department: str = "portal"  # Current active department/specialist
    departments_visited: List[str] = field(default_factory=list)

    # Customer (if recognized)
    customer: Optional[dict] = None
    customer_id: Optional[int] = None
    is_recognized: bool = False
    open_tickets: List[dict] = field(default_factory=list)

    # Caller info (collected this call)
    caller_name: str = ""
    caller_phone: str = ""
    caller_company: str = ""
    caller_site: str = ""
    caller_role: str = ""

    # Tickets in progress (one per department)
    tickets_in_progress: Dict[str, dict] = field(default_factory=dict)

    # Completed tickets
    completed_tickets: List[dict] = field(default_factory=list)

    # Ticket actions taken (for recognized callers)
    ticket_actions: List[dict] = field(default_factory=list)

    # Transcript
    transcript_lines: List[dict] = field(default_factory=list)

    # Audio
    audio_frames: List[bytes] = field(default_factory=list)
    sample_rate: int = 48000

    # FAQ context
    faq_context: Optional[str] = None

    def get_current_ticket(self) -> dict:
        """Get the ticket in progress for current department."""
        return self.tickets_in_progress.get(self.department, {})

    def set_ticket_field(self, field_name: str, value: str):
        """Set a field on the current department's ticket."""
        if self.department not in self.tickets_in_progress:
            self.tickets_in_progress[self.department] = {}
        self.tickets_in_progress[self.department][field_name] = value

    def get_ticket_field(self, field_name: str) -> Optional[str]:
        """Get a field from the current department's ticket."""
        return self.tickets_in_progress.get(self.department, {}).get(field_name)

    def add_transcript_line(self, speaker: str, text: str):
        """Add a line to the transcript."""
        self.transcript_lines.append({
            "timestamp": datetime.now().strftime("%H:%M:%S"),
            "speaker": speaker,
            "text": text,
            "department": self.department
        })

    def get_full_transcript(self) -> str:
        """Get the full transcript as a formatted string."""
        lines = []
        for entry in self.transcript_lines:
            speaker_label = "Grace" if entry["speaker"] == "grace" else "Caller"
            lines.append(f"[{entry['timestamp']}] {speaker_label}: {entry['text']}")
        return "\n".join(lines)

    def switch_department(self, new_dept: str):
        """Switch to a new department (maps to agent transfer in multi-agent system)."""
        if new_dept != self.department:
            self.department = new_dept
            if new_dept not in self.departments_visited:
                self.departments_visited.append(new_dept)
            if new_dept not in self.tickets_in_progress:
                self.tickets_in_progress[new_dept] = {}
            # Update phase based on department
            if new_dept == "closing":
                self.phase = "closing"
            elif new_dept != "portal":
                self.phase = "intake"

    def finalize_ticket(self) -> Optional[dict]:
        """Mark current ticket as complete and return it."""
        current = self.tickets_in_progress.get(self.department)
        if current:
            ticket = {
                "category": self.department,
                "caller_name": self.caller_name,
                "caller_phone": self.caller_phone,
                "caller_company": self.caller_company,
                "customer_id": self.customer_id,
                **current
            }
            self.completed_tickets.append(ticket)
            self.tickets_in_progress[self.department] = {}
            return ticket
        return None

    def record_ticket_action(self, action: str, ticket_id: int, **kwargs):
        """Record an action taken on an existing ticket."""
        self.ticket_actions.append({
            "action": action,
            "ticket_id": ticket_id,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        })

    def to_dict(self) -> dict:
        """Convert state to dictionary for serialization."""
        return {
            "call_id": self.call_id,
            "call_start": self.call_start.isoformat(),
            "phase": self.phase,
            "department": self.department,
            "departments_visited": self.departments_visited,
            "customer_id": self.customer_id,
            "is_recognized": self.is_recognized,
            "caller_name": self.caller_name,
            "caller_phone": self.caller_phone,
            "caller_company": self.caller_company,
            "caller_site": self.caller_site,
            "tickets_in_progress": self.tickets_in_progress,
            "completed_tickets": self.completed_tickets,
            "ticket_actions": self.ticket_actions,
            "transcript_lines": self.transcript_lines
        }

    def __repr__(self):
        return (
            f"CallState(call_id={self.call_id!r}, phase={self.phase!r}, "
            f"department={self.department!r}, caller={self.caller_name!r}, "
            f"recognized={self.is_recognized})"
        )


# Required fields per department - aligned with multi-agent specialist requirements
REQUIRED_FIELDS = {
    "service": ["caller_name", "caller_phone", "site", "issue", "urgency"],
    "billing": ["caller_name", "caller_phone", "invoice_or_topic"],
    "parts": ["caller_name", "caller_phone", "part_info"],
    "projects": ["caller_name", "caller_phone", "project_scope", "timeline"],
    "maintenance": ["caller_name", "caller_phone", "site", "question"],
    "controls": ["caller_name", "caller_phone", "site", "bas_type", "issue"],
    "general": ["caller_name", "caller_phone", "topic"],
    "portal": ["caller_name", "caller_phone"],  # Portal just needs basic info before routing
    "office": ["caller_name", "caller_phone", "topic"],
}


def get_missing_required_fields(state: CallState) -> List[str]:
    """Get list of missing required fields for current department."""
    required = REQUIRED_FIELDS.get(state.department, REQUIRED_FIELDS["general"])
    missing = []

    for fld in required:
        if fld == "caller_name" and not state.caller_name:
            missing.append("name")
        elif fld == "caller_phone" and not state.caller_phone:
            missing.append("callback number")
        elif fld not in ["caller_name", "caller_phone"]:
            if not state.get_ticket_field(fld):
                natural_names = {
                    "site": "site or building name",
                    "issue": "what's going on with the equipment",
                    "urgency": "how urgent this is",
                    "invoice_or_topic": "the invoice number or billing question",
                    "part_info": "what part they need",
                    "project_scope": "what the project involves",
                    "timeline": "their timeline or deadline",
                    "question": "their question",
                    "bas_type": "what BAS or controls system they have",
                    "topic": "what they need help with"
                }
                missing.append(natural_names.get(fld, fld))

    return missing


def is_ticket_complete(state: CallState) -> bool:
    """Check if current department's ticket has all required fields."""
    return len(get_missing_required_fields(state)) == 0

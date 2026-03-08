#!/usr/bin/env python3
"""
HVAC Grace V2 Stress Test Suite
Comprehensive scenarios testing single-agent architecture with:
- Customer recognition (recurring callers)
- Ticket modifications (status check, update, cancel)
- FAQ handling
- Multi-department context switching
- Dynamic prompt rebuilding
"""

# =============================================================================
# TEST CATEGORIES
# =============================================================================

# Pre-seeded customer data for recognition tests
# These should be inserted into database before running tests
PRESEEDED_CUSTOMERS = [
    {
        "name": "Robert Thompson",
        "phone": "5551002000",
        "company": "Thompson Industries",
        "notes": "Manufacturing facility, usually urgent calls",
        "total_calls": 5
    },
    {
        "name": "Jennifer Martinez",
        "phone": "5553334444",
        "company": "Martinez Property Group",
        "notes": "Property manager, manages 10+ buildings",
        "total_calls": 12
    },
    {
        "name": "Dr. Patricia Williams",
        "phone": "5559110001",
        "company": "City General Hospital",
        "notes": "Chief of Surgery - always treat as priority",
        "total_calls": 3
    },
    {
        "name": "David Chen",
        "phone": "5558889999",
        "company": "Chen Development Corporation",
        "notes": "Developer, primarily projects work",
        "total_calls": 8
    },
    {
        "name": "Sandra Williams",
        "phone": "5556667777",
        "company": "Williams Commercial Properties",
        "notes": "Has PM contract for 5 buildings",
        "total_calls": 20
    }
]

# Pre-seeded open tickets for ticket action tests
PRESEEDED_TICKETS = [
    {
        "id": 10001,
        "caller_name": "Robert Thompson",
        "caller_phone": "5551002000",
        "category": "service",
        "status": "assigned",
        "issue_brief": "York chiller making grinding noise",
        "site_name": "Thompson Industries",
        "assigned_to": "Mike T"
    },
    {
        "id": 10002,
        "caller_name": "Jennifer Martinez",
        "caller_phone": "5553334444",
        "category": "service",
        "status": "in_progress",
        "issue_brief": "Boiler no heat at Sunset Apartments",
        "site_name": "Sunset Apartments",
        "assigned_to": "Dave R"
    },
    {
        "id": 10003,
        "caller_name": "Sandra Williams",
        "caller_phone": "5556667777",
        "category": "parts",
        "status": "pending_parts",
        "issue_brief": "Waiting on compressor for AHU-3",
        "site_name": "Commerce Blvd Building 2"
    }
]


# =============================================================================
# CUSTOMER RECOGNITION SCENARIOS
# =============================================================================

RECOGNITION_SCENARIOS = {
    "recog_1": {
        "name": "Recognized Caller - Simple Follow-up",
        "description": "Returning customer calling about their existing open ticket",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[0],  # Robert Thompson
        "pre_seed_ticket": PRESEEDED_TICKETS[0],
        "expected_recognition": True,
        "expected_departments": ["service"],
        "expected_tickets": 0,  # Following up, not new ticket
        "expected_behaviors": [
            "greet_by_name",
            "reference_open_ticket",
            "no_ask_for_name",
            "no_ask_for_phone"
        ],
        "script": [
            "Hi, this is Robert Thompson.",
            "I'm calling about my open service ticket.",
            "The chiller at Thompson Industries.",
            "Yes, ticket 10001.",
            "I just wanted to check on the status.",
            "When is the tech expected to arrive?",
            "Okay, that's helpful. Thank you.",
            "That's all I needed.",
            "[HANGUP]"
        ]
    },
    "recog_2": {
        "name": "Recognized Caller - New Issue",
        "description": "Returning customer with NEW issue at different building",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[1],  # Jennifer Martinez
        "pre_seed_ticket": PRESEEDED_TICKETS[1],
        "expected_recognition": True,
        "expected_departments": ["service"],
        "expected_tickets": 1,  # New ticket despite being recognized
        "expected_behaviors": [
            "greet_by_name",
            "offer_open_ticket_reference",
            "collect_new_ticket_info",
            "no_ask_for_name"
        ],
        "script": [
            "Hi, Jennifer Martinez calling.",
            "I need to report a new issue.",
            "This is not about the Sunset Apartments ticket.",
            "This is at Oak Manor, 200 Oak Street.",
            "The RTU on the roof is making a terrible noise.",
            "It's a Carrier 10 ton unit.",
            "Started yesterday, loud grinding sound.",
            "This can wait until tomorrow, not an emergency.",
            "Call me at this number when the tech is on the way.",
            "Thank you!",
            "[HANGUP]"
        ]
    },
    "recog_3": {
        "name": "Recognized Caller - Ticket Update",
        "description": "Returning customer wants to update their open ticket",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[1],  # Jennifer Martinez
        "pre_seed_ticket": PRESEEDED_TICKETS[1],
        "expected_recognition": True,
        "expected_departments": ["service"],
        "expected_tickets": 0,
        "expected_ticket_actions": ["update"],
        "expected_behaviors": [
            "acknowledge_update_request",
            "confirm_change"
        ],
        "script": [
            "Hi, it's Jennifer Martinez.",
            "I need to update my open ticket.",
            "The one for Sunset Apartments.",
            "The contact phone number changed.",
            "The new number for Tony is 555-999-8888.",
            "Also, he'll be available after 2 PM today.",
            "Yes, that's all. Thanks!",
            "[HANGUP]"
        ]
    },
    "recog_4": {
        "name": "Recognized Caller - Ticket Cancellation",
        "description": "Returning customer wants to cancel their ticket",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[2],  # Sandra Williams (parts ticket)
        "pre_seed_ticket": PRESEEDED_TICKETS[2],
        "expected_recognition": True,
        "expected_departments": ["parts"],
        "expected_tickets": 0,
        "expected_ticket_actions": ["cancel"],
        "expected_behaviors": [
            "confirm_cancellation",
            "ask_for_reason"
        ],
        "script": [
            "Hi, this is Sandra Williams.",
            "I need to cancel my parts order.",
            "The compressor for Building 2.",
            "We found one from another vendor.",
            "Yes, please cancel ticket 10003.",
            "Thank you!",
            "[HANGUP]"
        ]
    },
    "recog_5": {
        "name": "Unrecognized Caller - Full Intake",
        "description": "New caller requires full information collection",
        "pre_seed_customer": None,
        "expected_recognition": False,
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "expected_behaviors": [
            "standard_greeting",
            "ask_for_name",
            "ask_for_phone",
            "full_intake"
        ],
        "script": [
            "Hi, I need to schedule a service call.",
            "My name is Thomas Henderson.",
            "555-777-1234",
            "Henderson Manufacturing",
            "We're at 5000 Industrial Way in Norristown.",
            "Our air handler stopped working.",
            "It's a Trane unit in the mechanical room.",
            "Serves the main production floor.",
            "No cooling at all. Started this morning.",
            "Yes, we need someone today. Production is affected.",
            "Overtime is fine.",
            "I'll be the contact.",
            "That's everything.",
            "[HANGUP]"
        ]
    }
}


# =============================================================================
# FAQ SCENARIOS
# =============================================================================

FAQ_SCENARIOS = {
    "faq_1": {
        "name": "FAQ - Business Hours",
        "description": "Caller asks about office hours mid-conversation",
        "expected_faq_triggers": ["hours"],
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "script": [
            "Hi, I need to place a service call.",
            "But first, what are your office hours?",
            "Oh good. I'm John Davis.",
            "555-123-4000",
            "Davis Office Park",
            "100 Corporate Drive, Philadelphia",
            "Our rooftop unit is making noise.",
            "Carrier 7.5 ton, on the roof.",
            "Serves the second floor offices.",
            "Loud vibration sound started yesterday.",
            "Not an emergency, but please send someone this week.",
            "I'll be the contact.",
            "Thanks!",
            "[HANGUP]"
        ]
    },
    "faq_2": {
        "name": "FAQ - Residential Rejection",
        "description": "Caller has residential issue - should be politely declined",
        "expected_faq_triggers": ["residential"],
        "expected_departments": [],
        "expected_tickets": 0,
        "expected_behaviors": [
            "politely_decline",
            "explain_commercial_only"
        ],
        "script": [
            "Hi, my home air conditioner isn't working.",
            "It's at my house on Pine Street.",
            "Oh, you only do commercial?",
            "Do you have any recommendations for residential?",
            "Okay, thank you anyway.",
            "[HANGUP]"
        ]
    },
    "faq_3": {
        "name": "FAQ - Service Area Question",
        "description": "Caller asks if their location is in service area",
        "expected_faq_triggers": ["service_area"],
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "script": [
            "Hi, do you service buildings in Wilmington, Delaware?",
            "Oh, only the Philadelphia area?",
            "Actually, I have a building in Chester that needs service.",
            "That's in your area, right?",
            "Great! My name is Lisa Park.",
            "555-222-3456",
            "Park Retail Group",
            "Chester Shopping Center, 500 Chester Pike",
            "Our split system is leaking water.",
            "Mitsubishi mini split in the manager's office.",
            "Started two days ago, getting worse.",
            "Tomorrow is fine.",
            "Call me when the tech is on the way.",
            "Thank you!",
            "[HANGUP]"
        ]
    },
    "faq_4": {
        "name": "FAQ - Emergency Availability",
        "description": "Caller asks about 24/7 emergency service",
        "expected_faq_triggers": ["emergency_service"],
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "script": [
            "Hi, do you have 24/7 emergency service?",
            "Good, because we have an emergency right now.",
            "Our walk-in cooler just died.",
            "My name is Marco Gonzales.",
            "555-888-7777",
            "Gonzales Restaurant Group",
            "Main Street Bistro, 200 Main Street, Center City",
            "The walk-in cooler compressor failed.",
            "In the kitchen, behind the prep area.",
            "Inventory worth $10,000 at risk.",
            "Yes, this is an emergency. We need someone immediately.",
            "Overtime is fine, whatever it takes.",
            "I'm here at the restaurant, call me.",
            "Please hurry!",
            "[HANGUP]"
        ]
    },
    "faq_5": {
        "name": "FAQ - Multiple Questions",
        "description": "Caller asks multiple FAQ questions during one call",
        "expected_faq_triggers": ["hours", "payment"],
        "expected_departments": ["billing"],
        "expected_tickets": 1,
        "script": [
            "Hi, I have a few questions.",
            "First, what are your office hours?",
            "And do you accept credit cards for payment?",
            "Okay, thanks. I actually need to discuss an invoice.",
            "My name is Karen White.",
            "555-444-5678",
            "White Property Management",
            "Invoice number 99876.",
            "I think we were charged twice for the same visit.",
            "Can someone review it and call me back?",
            "Thank you!",
            "[HANGUP]"
        ]
    }
}


# =============================================================================
# CONTEXT SWITCHING SCENARIOS
# =============================================================================

CONTEXT_SWITCHING_SCENARIOS = {
    "switch_1": {
        "name": "Triple Department - Sequential Switches",
        "description": "Caller needs service, billing, AND parts - handled sequentially",
        "expected_departments": ["service", "billing", "parts"],
        "expected_tickets": 3,
        "context_switches": 2,
        "script": [
            "Hi, I have several things I need help with today.",
            "First, our rooftop unit stopped cooling.",
            "My name is Andrew Miller.",
            "555-111-2222",
            "Miller Office Complex",
            "1000 Business Park Drive, King of Prussia",
            "It's a Trane 15 ton rooftop unit.",
            "On the roof above the main lobby.",
            "Serves the first and second floor.",
            "Just warm air blowing. Started this morning.",
            "Yes, we need someone today. Building is getting warm.",
            "Overtime is okay.",
            "Call the building manager at 555-111-3333.",
            "Also, I have a billing question.",
            "Invoice 45000 from last month.",
            "The labor hours seem high - 8 hours for a filter change?",
            "Please have someone review it.",
            "One more thing - we need to order filters.",
            "For that same Trane unit - model 4MCW006.",
            "We need 4 filters, 20x25x4.",
            "Not urgent, for our next PM visit.",
            "That covers everything. Thank you!",
            "[HANGUP]"
        ]
    },
    "switch_2": {
        "name": "Back-and-Forth Switching",
        "description": "Caller switches between service and billing, then back to service",
        "expected_departments": ["service", "billing", "service"],
        "expected_tickets": 2,
        "context_switches": 2,
        "script": [
            "Hi, my AC isn't working.",
            "My name is Beth Collins.",
            "555-333-4444",
            "Collins Retail Store",
            "500 Market Street, Philadelphia",
            "Actually wait, before we continue...",
            "I need to check on an old invoice first.",
            "Invoice 30001 - did we ever pay that?",
            "Can you check our account?",
            "Okay, just have billing call me about that.",
            "Now back to the AC problem.",
            "It's a split system.",
            "In the back office area.",
            "The indoor unit is frozen solid.",
            "Ice all over the coils.",
            "Started yesterday afternoon.",
            "Yes, we need service today.",
            "I'm the contact.",
            "That's it!",
            "[HANGUP]"
        ]
    },
    "switch_3": {
        "name": "Rapid-Fire Multi-Department",
        "description": "Property manager with issues spanning all major departments",
        "expected_departments": ["service", "maintenance", "projects", "controls"],
        "expected_tickets": 4,
        "context_switches": 3,
        "script": [
            "Hi, I'm the facilities director and I have a lot going on.",
            "My name is Chris Palmer.",
            "555-555-6666",
            "Palmer Commercial Properties",
            "First - emergency service at Building A, 100 Alpha Street.",
            "Boiler completely failed. No heat. 200 employees freezing.",
            "Weil-McLain commercial boiler in the basement.",
            "This is an emergency - need someone now.",
            "After hours fine. Call super at 555-555-0001.",
            "Second - maintenance contract question for Building B.",
            "Building B is at 200 Beta Boulevard.",
            "We want to add two more RTUs to our PM agreement.",
            "Have your maintenance team call me.",
            "Third - we need a project quote for Building C.",
            "Building C at 300 Charlie Court needs a chiller replacement.",
            "Current chiller is 20 years old, 150 tons.",
            "Budget is around $200K, need proposal by end of month.",
            "Call me about that one too.",
            "Fourth - BAS issue at Building D.",
            "Building D, 400 Delta Drive, Niagara system.",
            "Multiple sensors showing offline.",
            "Not emergency but affecting comfort complaints.",
            "Send someone when available.",
            "That's everything!",
            "[HANGUP]"
        ]
    },
    "switch_4": {
        "name": "Interrupt and Resume",
        "description": "Caller starts one issue, gets interrupted by emergency, returns to original",
        "expected_departments": ["maintenance", "service", "maintenance"],
        "expected_tickets": 2,
        "context_switches": 2,
        "script": [
            "Hi, I wanted to discuss our maintenance contract.",
            "My name is Diana Ross.",
            "555-777-8888",
            "Ross Medical Center",
            "We have two buildings on PM with you.",
            "Actually hold on - I'm getting an urgent page...",
            "Okay I'm back. We have an emergency at our satellite clinic.",
            "The satellite clinic is at 1000 Health Way.",
            "Their HVAC completely failed.",
            "It's a Carrier rooftop unit, 20 tons.",
            "In the mechanical well on the roof.",
            "Serves the entire clinic - exam rooms and waiting area.",
            "No cooling at all. Patients are uncomfortable.",
            "Started about an hour ago.",
            "Yes, this is urgent. Medical facility.",
            "Overtime is fine. Call clinic manager at 555-777-0001.",
            "Now back to the maintenance question.",
            "At our main campus, we want quarterly PM instead of semi-annual.",
            "Main campus is at 2000 Medical Drive.",
            "Can someone call me about changing the contract?",
            "Thank you for handling both of those!",
            "[HANGUP]"
        ]
    },
    "switch_5": {
        "name": "Same-Site Multi-Issue",
        "description": "Multiple issues at same site spanning departments",
        "expected_departments": ["service", "controls", "parts"],
        "expected_tickets": 3,
        "context_switches": 2,
        "script": [
            "Hi, we have several problems at our data center.",
            "My name is Eric Zhang.",
            "555-888-9999",
            "Zhang Technology Solutions",
            "All at one location - 5000 Server Farm Road.",
            "First, CRAC unit 3 is not cooling properly.",
            "Liebert 20 ton, showing high discharge temp.",
            "In server hall B, row 12.",
            "Cools critical server racks.",
            "Not failed yet but trending bad.",
            "Need someone today to look at it.",
            "I'm the contact for service calls.",
            "Second issue - building automation problem.",
            "Our Niagara system isn't logging data.",
            "Trend logs stopped 3 days ago.",
            "Need a controls tech to check the historian.",
            "Can be scheduled for this week.",
            "Third - we need to order a spare fan motor.",
            "For CRAC unit 2, same location.",
            "Model number is EC225-3.",
            "Want to keep one on site as spare.",
            "Not urgent, stock order.",
            "Got all that?",
            "[HANGUP]"
        ]
    }
}


# =============================================================================
# EDGE CASE SCENARIOS
# =============================================================================

EDGE_CASE_SCENARIOS = {
    "edge_1": {
        "name": "Ambiguous Department Start",
        "description": "Caller doesn't clearly indicate department initially",
        "expected_departments": ["general", "service"],
        "expected_tickets": 1,
        "script": [
            "Hi, I need some help.",
            "I'm not sure who I need to talk to.",
            "We're having problems with our building.",
            "The temperature is all over the place.",
            "Some areas too hot, some too cold.",
            "My name is Frank Adams.",
            "555-999-1111",
            "Adams Law Firm",
            "300 Legal Plaza, Center City",
            "I think it's an air conditioning issue.",
            "We have multiple units on the roof.",
            "Carrier systems, maybe 5 years old.",
            "This has been going on for a week.",
            "It's not an emergency but clients are complaining.",
            "Someone should look at it soon.",
            "I'm the office manager, call me.",
            "Thank you.",
            "[HANGUP]"
        ]
    },
    "edge_2": {
        "name": "Extremely Detailed Caller",
        "description": "Caller provides excessive technical detail",
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "script": [
            "Hi, I need service on my chiller.",
            "It's a Trane CVHE centrifugal chiller.",
            "Model CVHE525, serial number 123456ABC.",
            "500 tons nominal capacity.",
            "Uses R-134a refrigerant, 800 pounds charge.",
            "Variable speed drive on the compressor.",
            "We're seeing high condenser approach temps.",
            "Approach is 12 degrees, should be 5.",
            "Discharge pressure running 165 PSI.",
            "Suction at 45 PSI, superheat looks okay.",
            "Oil pressure differential is low.",
            "Bearing temps running 5 degrees higher than normal.",
            "My name is Gary Technical.",
            "555-000-1234",
            "Technical Industries",
            "1000 Engineering Drive, Conshohocken",
            "In the central plant, basement level 2.",
            "Serves the entire 500,000 square foot building.",
            "Not failed yet but we're worried.",
            "Need diagnostic visit.",
            "Call our chief engineer at 555-000-5678.",
            "That's everything.",
            "[HANGUP]"
        ]
    },
    "edge_3": {
        "name": "Minimal Information Caller",
        "description": "Caller provides bare minimum info, needs lots of prompting",
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "expected_behaviors": [
            "ask_multiple_followups",
            "patient_prompting"
        ],
        "script": [
            "My AC broke.",
            "Johnson.",
            "555-222-0000",
            "Some office building.",
            "Downtown somewhere.",
            "I don't know the address exactly.",
            "Maybe 400 Broad Street?",
            "It's not cooling.",
            "I don't know what kind.",
            "On the roof I think.",
            "Yeah I guess we need someone.",
            "Today would be good.",
            "Sure, call me.",
            "Okay bye.",
            "[HANGUP]"
        ]
    },
    "edge_4": {
        "name": "Frustrated/Angry Caller",
        "description": "Caller is upset about previous service",
        "expected_departments": ["service", "general"],
        "expected_tickets": 1,
        "expected_behaviors": [
            "empathy_acknowledgment",
            "de_escalation"
        ],
        "script": [
            "I am so frustrated with your company right now!",
            "Your tech was just here yesterday and the problem isn't fixed!",
            "My name is Helen Upset and I've been a customer for 10 years.",
            "555-333-0000",
            "Upset Enterprises",
            "5000 Frustration Avenue",
            "The AC is STILL not working!",
            "I don't care what kind it is - just fix it!",
            "He said he fixed it but it's doing the same thing.",
            "Blowing warm air just like before.",
            "I've had to send employees home!",
            "This is unacceptable!",
            "Yes I need someone back out here TODAY.",
            "And I want to speak to a manager about this.",
            "Someone needs to make this right.",
            "Fine, have them call me.",
            "This better get resolved.",
            "[HANGUP]"
        ]
    },
    "edge_5": {
        "name": "Language Barrier",
        "description": "Caller has limited English, needs patience",
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "expected_behaviors": [
            "patient_communication",
            "clarification_requests"
        ],
        "script": [
            "Hello, AC problem.",
            "My name... Carlos Mendez.",
            "Phone... 555-444-0000.",
            "Restaurant... El Sol.",
            "200 South Street.",
            "AC no work. Very hot.",
            "Kitchen... AC stop.",
            "How you say... the roof machine.",
            "Yes, rooftop. Big unit.",
            "Very hot in kitchen. Cannot cook.",
            "Today please. Emergency.",
            "Okay. You call me?",
            "Thank you very much!",
            "[HANGUP]"
        ]
    }
}


# =============================================================================
# COMBINED STRESS SCENARIOS (Multiple challenges at once)
# =============================================================================

COMBINED_STRESS_SCENARIOS = {
    "stress_1": {
        "name": "Recognized Caller + Multi-Department + FAQ",
        "description": "Known customer with open ticket, new issues, and FAQ questions",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[3],  # David Chen
        "expected_recognition": True,
        "expected_departments": ["projects", "service", "billing"],
        "expected_tickets": 2,  # projects + service (billing is just question)
        "expected_faq_triggers": ["hours"],
        "script": [
            "Hi, David Chen here.",
            "A couple of things today.",
            "First, what are your office hours for project meetings?",
            "Okay good. I have a new project quote request.",
            "Different from the Innovation Way project.",
            "This is for 600 Tech Park, a new 40,000 sf building.",
            "Need HVAC design and install.",
            "Timeline is 6 months.",
            "Budget around $500K.",
            "Have someone call me to set up a site walk.",
            "Also, we have an issue at our existing building.",
            "At 500 Innovation Way.",
            "One of the VAV boxes is stuck open.",
            "Zone 12 on the 3rd floor, always calling for cooling.",
            "Trane VAV, probably actuator issue.",
            "Not emergency but affecting comfort.",
            "Send someone when available.",
            "Call me for scheduling.",
            "And quick billing question - is my Innovation Way project on a payment plan?",
            "Just have billing confirm our payment schedule.",
            "That's everything!",
            "[HANGUP]"
        ]
    },
    "stress_2": {
        "name": "New Caller + Ticket Action Confusion",
        "description": "New caller mentions ticket number (not theirs) causing potential confusion",
        "expected_recognition": False,
        "expected_departments": ["service"],
        "expected_tickets": 1,
        "script": [
            "Hi, my neighbor told me to call you.",
            "They had ticket number 10001 I think?",
            "But I need my own service call.",
            "My name is Isabel Torres.",
            "555-666-0000",
            "Torres Auto Body",
            "100 Industrial Road, next to Thompson Industries.",
            "Our exhaust fan in the paint booth isn't working.",
            "It's a roof-mounted exhaust fan.",
            "Pulls fumes out of the paint booth.",
            "Completely stopped. Can't do any painting.",
            "This is an emergency for us - safety issue.",
            "Need someone today.",
            "Overtime is fine.",
            "I'm here all day, call me.",
            "Thanks!",
            "[HANGUP]"
        ]
    },
    "stress_3": {
        "name": "Recognized + Ticket Status + New Emergency",
        "description": "Known caller checks ticket status then reports new emergency",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[4],  # Sandra Williams
        "pre_seed_ticket": PRESEEDED_TICKETS[2],
        "expected_recognition": True,
        "expected_departments": ["parts", "service"],
        "expected_tickets": 1,
        "expected_ticket_actions": ["status_check"],
        "script": [
            "Hi Sandra Williams calling.",
            "First, what's the status on my parts order?",
            "The compressor for Building 2.",
            "Okay thanks for that update.",
            "Actually I have an emergency now.",
            "Building 4 at 400 Commerce Way.",
            "The chiller just tripped offline.",
            "York centrifugal, 200 tons.",
            "In the mechanical penthouse.",
            "Entire building has no cooling.",
            "This is our headquarters - 300 people.",
            "We need someone immediately.",
            "Cost doesn't matter.",
            "Call me directly, I'm heading there now.",
            "This is critical!",
            "[HANGUP]"
        ]
    },
    "stress_4": {
        "name": "Multi-Site + Recognition + Cancel + New Tickets",
        "description": "Known property manager: cancels one ticket, creates new ones at multiple sites",
        "pre_seed_customer": PRESEEDED_CUSTOMERS[1],  # Jennifer Martinez
        "pre_seed_ticket": PRESEEDED_TICKETS[1],
        "expected_recognition": True,
        "expected_departments": ["service"],
        "expected_tickets": 2,
        "expected_ticket_actions": ["cancel"],
        "script": [
            "Hi Jennifer Martinez here.",
            "Few things to cover.",
            "First, cancel the Sunset Apartments ticket.",
            "Turns out it was just the thermostat batteries.",
            "Maintenance guy fixed it.",
            "Now I have two NEW issues at different buildings.",
            "First building is Maple Grove Condos.",
            "1000 Maple Street.",
            "Elevator machine room is too hot.",
            "The split system serving it stopped working.",
            "Mitsubishi mini split.",
            "Elevator company said it needs to be fixed today or they shut down the elevator.",
            "This is urgent - it's a high rise.",
            "Call building super at 555-MAPLE.",
            "Second building is Riverside Office Park.",
            "2000 River Road.",
            "RTU-3 is short cycling.",
            "Lennox 10 ton, on the roof section C.",
            "Serves the east wing offices.",
            "Not emergency but needs attention this week.",
            "Call me for that one.",
            "Got all that?",
            "[HANGUP]"
        ]
    }
}


# =============================================================================
# MASTER SCENARIO COLLECTION
# =============================================================================

V2_STRESS_SCENARIOS = {
    **RECOGNITION_SCENARIOS,
    **FAQ_SCENARIOS,
    **CONTEXT_SWITCHING_SCENARIOS,
    **EDGE_CASE_SCENARIOS,
    **COMBINED_STRESS_SCENARIOS
}

# Scenario counts for reporting
SCENARIO_COUNTS = {
    "recognition": len(RECOGNITION_SCENARIOS),
    "faq": len(FAQ_SCENARIOS),
    "context_switching": len(CONTEXT_SWITCHING_SCENARIOS),
    "edge_cases": len(EDGE_CASE_SCENARIOS),
    "combined_stress": len(COMBINED_STRESS_SCENARIOS),
    "total": len(V2_STRESS_SCENARIOS)
}


if __name__ == "__main__":
    print("HVAC Grace V2 Stress Test Scenarios")
    print("=" * 50)
    print(f"Recognition Tests:     {SCENARIO_COUNTS['recognition']}")
    print(f"FAQ Tests:             {SCENARIO_COUNTS['faq']}")
    print(f"Context Switch Tests:  {SCENARIO_COUNTS['context_switching']}")
    print(f"Edge Case Tests:       {SCENARIO_COUNTS['edge_cases']}")
    print(f"Combined Stress Tests: {SCENARIO_COUNTS['combined_stress']}")
    print("-" * 50)
    print(f"TOTAL SCENARIOS:       {SCENARIO_COUNTS['total']}")
    print()
    print("Pre-seeded Customers:", len(PRESEEDED_CUSTOMERS))
    print("Pre-seeded Tickets:", len(PRESEEDED_TICKETS))

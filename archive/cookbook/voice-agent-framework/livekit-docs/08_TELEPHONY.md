# Telephony Integration

**Source:** https://docs.livekit.io/agents/start/telephony/

## Overview

LiveKit enables voice AI agents to handle phone calls through SIP (Session Initiation Protocol) integration. The system bridges phone calls into LiveKit rooms as special participant types.

## Key Features

- **Inbound and outbound calling support**
- **DTMF support** for tone-based input
- **SIP REFER functionality** for call transfers
- **Voicemail detection capabilities**
- **Call transfer to other numbers**

## Setup Requirements

1. Deploy a basic voice AI agent using LiveKit's quickstart
2. Set up SIP infrastructure (LiveKit Phone Numbers or third-party SIP provider)
3. Configure dispatch rules and trunk settings

## Agent Configuration for Telephony

Agents require explicit naming to disable automatic dispatch:

```python
@server.rtc_session(agent_name="hvac-support")
async def my_agent(ctx):
    # Your agent code
    pass
```

## Noise Cancellation for Telephony

Use telephony-optimized noise cancellation:

```python
from livekit.plugins import noise_cancellation
from livekit import rtc

room_options=room_io.RoomOptions(
    audio_input=room_io.AudioInputOptions(
        noise_cancellation=lambda params: 
            noise_cancellation.BVCTelephony() 
            if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP 
            else noise_cancellation.BVC()
    ),
)
```

## Inbound Calls

### Dispatch Rules

Create dispatch rules to route calls to specific agents:

```python
# Via LiveKit Cloud dashboard or API
# Route calls from +1555... to agent "hvac-support"
```

### Initial Greeting

```python
await session.start(room=ctx.room, agent=MyAgent())

# Important: Generate greeting AFTER session starts
await session.generate_reply(
    instructions="Greet the caller warmly."
)
```

## Outbound Calls

### Creating Outbound Calls

```python
from livekit import api

# Create SIP participant
request = api.CreateSIPParticipantRequest(
    sip_trunk_id="trunk-id",
    sip_call_to="+15551234567",
    room_name="my-room",
    participant_identity="outbound-caller",
)

lk_api = api.LiveKitAPI()
await lk_api.sip.create_sip_participant(request)
```

### Waiting for Connection

```python
# Wait for the call to be answered
await ctx.wait_for_participant()

# Then start the session
await session.start(room=ctx.room, agent=OutboundAgent())
```

## Call Management

### Hanging Up

Use the `delete_room` API to end calls for all participants:

```python
await lk_api.room.delete_room(api.DeleteRoomRequest(room=room_name))
```

**Note:** If only the agent session ends, the user will continue to hear silence until they hang up.

### Call Transfers

Cold transfer to another number:

```python
await lk_api.sip.transfer_sip_participant(
    api.TransferSIPParticipantRequest(
        room_name=room_name,
        participant_identity=participant_identity,
        transfer_to="+15559876543",
    )
)
```

## DTMF Handling

Handle touch-tone input:

```python
@ctx.room.on("data_received")
def on_dtmf(data, participant, topic):
    if topic == "lk.dtmf":
        digits = data.decode()
        print(f"DTMF received: {digits}")
        # Handle menu selection, etc.
```

## SIP Participant Detection

Check if participant is from phone:

```python
from livekit import rtc

def is_phone_call(participant):
    return participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
```

## Best Practices

1. **Always use telephony-optimized noise cancellation** for phone calls
2. **Name your agents** to control dispatch routing
3. **Handle the greeting properly** - generate after session.start()
4. **Implement proper hangup** using delete_room to avoid zombie calls
5. **Consider latency** - phone calls may have higher latency than WebRTC
6. **Test DTMF handling** if using IVR-style menus

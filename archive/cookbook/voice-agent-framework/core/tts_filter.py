"""
TTS Filter Wrapper
Filters out tool call text, unwanted phrases, and normalizes text for natural speech.
"""

import re
from livekit.agents import tts, APIConnectOptions
from livekit.agents.tts import ChunkedStream, SynthesizeStream

# Patterns to remove from TTS output
FILTER_PATTERNS = [
    # Tool call patterns
    r'</?tool_call>',
    r'<tool_call>.*?</tool_call>',
    r'<tool_call>.*',
    r'\{"name":\s*"route_to_\w+".*',
    r'"name":\s*"route_to_\w+"',
    r'"arguments":\s*\{\}',

    # Transfer/routing phrases
    r"[^.!?]*transfer you[^.!?]*[.!?]?",
    r"[^.!?]*connect you[^.!?]*[.!?]?",
    r"[^.!?]*one moment[^.!?]*[.!?]?",
    r"[^.!?]*please hold[^.!?]*[.!?]?",
    r"[^.!?]*routing you[^.!?]*[.!?]?",
    r"[^.!?]*routing to[^.!?]*[.!?]?",
    r"[^.!?]*let me get you to[^.!?]*[.!?]?",
    r"[^.!?]*i'll transfer[^.!?]*[.!?]?",
    r"[^.!?]*i'll route[^.!?]*[.!?]?",

    # Internal error messages that should never be spoken
    r"[^.!?]*issue with routing[^.!?]*[.!?]?",
    r"[^.!?]*routing.*agent[^.!?]*[.!?]?",
    r"[^.!?]*closing agent[^.!?]*[.!?]?",
    r"[^.!?]*there was an issue[^.!?]*[.!?]?",
    r"[^.!?]*seems there was[^.!?]*[.!?]?",
    r"[^.!?]*it seems there[^.!?]*[.!?]?",

    # Department mentions
    r"[^.!?]*to our [a-z]+ team[^.!?]*[.!?]?",
    r"[^.!?]*controls team[^.!?]*[.!?]?",
    r"[^.!?]*service team[^.!?]*[.!?]?",
    r"[^.!?]*billing team[^.!?]*[.!?]?",
    r"[^.!?]*parts team[^.!?]*[.!?]?",
]

COMPILED_PATTERNS = [re.compile(p, re.IGNORECASE | re.DOTALL) for p in FILTER_PATTERNS]


def normalize_phone_number(match):
    """Convert phone number to speakable format: 215-527-0596 -> 2 1 5, 5 2 7, 0 5 9 6"""
    phone = match.group(0)
    digits = re.sub(r'\D', '', phone)
    if len(digits) == 10:
        return f"{' '.join(digits[0:3])}, {' '.join(digits[3:6])}, {' '.join(digits[6:10])}"
    elif len(digits) == 11 and digits[0] == '1':
        return f"{' '.join(digits[1:4])}, {' '.join(digits[4:7])}, {' '.join(digits[7:11])}"
    return phone


def normalize_address_number(match):
    """Convert address numbers to natural speech: 4300 -> forty-three hundred"""
    num_str = match.group(1)
    num = int(num_str)

    ones = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
    teens = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
             'seventeen', 'eighteen', 'nineteen']
    tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']

    if 100 <= num <= 9999:
        if num % 100 == 0:
            # 4300 -> "forty-three hundred"
            hundreds = num // 100
            if hundreds < 10:
                return ones[hundreds] + " hundred"
            elif hundreds < 20:
                return teens[hundreds - 10] + " hundred"
            else:
                t, o = divmod(hundreds, 10)
                return tens[t] + ("-" + ones[o] if o else "") + " hundred"
        else:
            # 4321 -> "forty-three twenty-one"
            first_two = num // 100
            last_two = num % 100

            def say_two_digit(n):
                if n == 0:
                    return "hundred"
                elif n < 10:
                    return "oh-" + ones[n]
                elif n < 20:
                    return teens[n - 10]
                else:
                    t, o = divmod(n, 10)
                    return tens[t] + ("-" + ones[o] if o else "")

            def say_first_two(n):
                if n < 10:
                    return ones[n]
                elif n < 20:
                    return teens[n - 10]
                else:
                    t, o = divmod(n, 10)
                    return tens[t] + ("-" + ones[o] if o else "")

            return say_first_two(first_two) + " " + say_two_digit(last_two)

    return num_str


def normalize_invoice_number(match):
    """Convert invoice numbers: 001-0034 -> oh oh one dash oh oh three four"""
    invoice = match.group(0)
    result = []
    for char in invoice:
        if char == '-':
            result.append('dash')
        elif char == '0':
            result.append('oh')
        elif char.isdigit():
            digit_words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
            result.append(digit_words[int(char)])
        else:
            result.append(char)
    return ' '.join(result)


def normalize_for_speech(text: str) -> str:
    """Normalize text for natural speech."""
    if not text:
        return text

    # Safety: Replace dashes between digits with spaces (prevents TTS "minus" reading)
    text = re.sub(r'(\d)-(\d)', r'\1 \2', text)

    # Phone numbers: 215-527-0596 or (215) 527-0596 or 2155270596
    text = re.sub(r'\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}', normalize_phone_number, text)

    # Invoice/reference numbers with dashes: 001-0034
    text = re.sub(r'\b\d{2,4}-\d{2,4}\b', normalize_invoice_number, text)

    # Address numbers before street names
    text = re.sub(r'\b(\d{3,5})\s+(?=[A-Z][a-z]+\s+(?:Street|Drive|Avenue|Road|Lane|Way|Boulevard|Blvd|St|Dr|Ave|Rd|Ln))',
                  normalize_address_number, text, flags=re.IGNORECASE)

    return text


def filter_text(text: str) -> str:
    if not text:
        return text

    original = text

    for pattern in COMPILED_PATTERNS:
        text = pattern.sub('', text)

    text = normalize_for_speech(text)

    text = re.sub(r'\s+', ' ', text)
    text = re.sub(r'\s+([.!?])', r'\1', text)
    text = re.sub(r'([.!?])\s*([.!?])', r'\1', text)
    text = re.sub(r'^\s*[.!?]\s*', '', text)
    text = text.strip()

    if text != original.strip() and len(original) - len(text) > 3:
        print(f"TTS_FILTER: '{original[:50]}' -> '{text[:50] if text else '[empty]'}")

    return text


class FilteredTTS(tts.TTS):
    def __init__(self, wrapped_tts: tts.TTS):
        super().__init__(
            capabilities=wrapped_tts.capabilities,
            sample_rate=wrapped_tts.sample_rate,
            num_channels=wrapped_tts.num_channels,
        )
        self._wrapped = wrapped_tts

    @property
    def model(self) -> str:
        return self._wrapped.model

    @property
    def provider(self) -> str:
        return self._wrapped.provider

    def synthesize(self, text: str, *, conn_options: APIConnectOptions = APIConnectOptions()) -> ChunkedStream:
        filtered = filter_text(text)
        if not filtered:
            return self._wrapped.synthesize(" ", conn_options=conn_options)
        return self._wrapped.synthesize(filtered, conn_options=conn_options)

    def stream(self, *, conn_options: APIConnectOptions = APIConnectOptions()) -> SynthesizeStream:
        return FilteredSynthesizeStream(self._wrapped.stream(conn_options=conn_options))


class FilteredSynthesizeStream(SynthesizeStream):
    def __init__(self, wrapped_stream: SynthesizeStream):
        self._wrapped = wrapped_stream
        self._buffer = ""

    def push_text(self, text: str) -> None:
        self._buffer += text
        if '<tool' in self._buffer and '</tool_call>' not in self._buffer:
            return
        filtered = filter_text(self._buffer)
        self._buffer = ""
        if filtered:
            self._wrapped.push_text(filtered)

    def flush(self) -> None:
        if self._buffer:
            filtered = filter_text(self._buffer)
            self._buffer = ""
            if filtered:
                self._wrapped.push_text(filtered)
        self._wrapped.flush()

    def end_input(self) -> None:
        if self._buffer:
            filtered = filter_text(self._buffer)
            if filtered:
                self._wrapped.push_text(filtered)
            self._buffer = ""
        self._wrapped.end_input()

    async def aclose(self) -> None:
        await self._wrapped.aclose()

    def __aiter__(self):
        return self._wrapped.__aiter__()

    async def __anext__(self):
        return await self._wrapped.__anext__()

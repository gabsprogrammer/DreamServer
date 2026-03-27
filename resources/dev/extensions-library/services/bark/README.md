# Bark TTS

Suno AI's transformer-based text-to-audio model. Generates highly expressive, realistic speech including laughter, sighs, and emotion — far beyond what traditional TTS can do. Supports 13 languages.

## What It Does

- Expressive speech with natural prosody, laughter, sighs, hesitation
- 13 language presets: English, German, Spanish, French, Hindi, Italian, Japanese, Korean, Polish, Portuguese, Russian, Turkish, Chinese
- Multiple speaker voices per language (10 per language)
- Non-verbal sounds: [laughter], [sighs], [gasps], [clears throat], [music]
- REST API compatible with n8n workflows

## Quick Start

```bash
dream enable bark
```

**Note:** First startup downloads ~5GB of models. This can take 10-20 minutes depending on your connection. Subsequent starts are instant.

Open **http://localhost:9200** to access the API docs.

## API Usage

### Generate Speech (Base64 response)
```bash
curl -X POST http://localhost:9200/tts \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello! [laughs] This is Bark TTS.", "voice_preset": "v2/en_speaker_6"}'
```

### Get Raw Audio (WAV)
```bash
curl -X POST http://localhost:9200/tts/stream \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello from Bark!", "voice_preset": "v2/en_speaker_3"}' \
  --output output.wav
```

### List Voice Presets
```bash
curl http://localhost:9200/voices
```

## Special Text Tokens

Bark understands non-verbal cues in brackets:
- `[laughter]` — add laughter
- `[sighs]` — add a sigh
- `[music]` — add a music clip
- `[gasps]` — add a gasp
- `[clears throat]` — throat clearing
- `...` — add natural pauses
- `♪` — singing mode

## VRAM Requirements

| Mode | VRAM |
|------|------|
| Full models | ~4GB |
| Small models (`BARK_USE_SMALL_MODELS=true`) | ~2GB |
| CPU offload | <1GB VRAM (slow) |

> **Apple Silicon / ARM64:** Bark runs in CPU mode on Apple Silicon. Inference is slower than GPU but fully functional.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BARK_USE_SMALL_MODELS` | `false` | Use smaller/faster models |
| `BARK_OFFLOAD_CPU` | `false` | Offload to CPU between requests |
| `BARK_PORT` | `9200` | External port |
| `BARK_API_KEY` | `` | API key for authentication (optional) |

## Data Persistence

- `./data/bark/models/` — Bark model cache (~5GB)
- `./data/bark/output/` — Generated audio files

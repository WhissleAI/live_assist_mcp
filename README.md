# Whissle for Claude Code

Two-in-one package: **MCP tools** (35+ tools for personal AI context) and **claude-voice** (Alt+V voice dictation with multi-speaker tracking).

## Quick Setup

```bash
git clone https://github.com/WhissleAI/whissle-claude.git && cd whissle-claude
./setup.sh              # interactive — prompts for everything
./setup.sh --all        # all clients (Claude Code + Cursor + Claude Desktop)
./setup.sh --claude-code
./setup.sh --mcp-only   # skip voice setup
./setup.sh --voice-only # skip MCP setup
```

The script installs all prerequisites, collects your Whissle token, validates it, and configures everything.

**Then run:**

```bash
claude-voice                              # launch Claude Code with voice
claude-voice --speakers karan,reviewer    # collaborative mode
```

## MCP Server (35+ Tools)

The MCP server connects Claude Code, Cursor, and Claude Desktop to the full Whissle AI gateway.

| Category | Tools |
|---|---|
| **Core Agent** | `ask_agent`, `deep_research`, `get_user_context`, `get_user_personality` |
| **Memory** | `search_memories`, `store_memory` |
| **Calendar** | `check_calendar`, `create_calendar_event`, `set_reminder` |
| **Email** | `check_email`, `send_email` |
| **Contacts** | `search_contacts` |
| **Google Drive** | `search_drive`, `save_to_sheet`, `read_from_sheet` |
| **Google Tasks** | `create_task`, `list_tasks`, `complete_task` |
| **Web Search** | `web_search`, `read_url`, `fetch_news`, `get_news` |
| **Finance** | `get_stock_price`, `get_crypto_price`, `convert_currency` |
| **Media** | `search_videos`, `generate_image`, `analyze_image`, `analyze_audio`, `analyze_video` |
| **Utilities** | `translate_text`, `calculate`, `run_code`, `analyze_document`, `extract_text_metadata` |
| **Navigation** | `search_places`, `get_directions` |
| **Weather** | `get_weather`, `daily_briefing` |
| **Scheduling** | `schedule_recurring`, `list_scheduled_tasks`, `cancel_scheduled_task` |
| **Settings** | `set_preference` |

### Manual MCP Setup

#### Option A: Cloud-hosted (SSE)

The MCP server is deployed on Cloud Run. Add the URL to your config:

**Cursor** — `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "url": "https://whissle-mcp-843574834406.us-central1.run.app/sse",
      "headers": {
        "X-User-Id": "YOUR_WHISSLE_USER_ID"
      }
    }
  }
}
```

#### Option B: Run locally (stdio)

```bash
git clone https://github.com/WhissleAI/whissle-claude.git && cd whissle-claude
python -m venv venv && source venv/bin/activate
pip install -e .
```

**Claude Code** — `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/whissle-claude/venv/bin/python",
      "args": ["/path/to/whissle-claude/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here",
        "WHISSLE_USER_NAME": "Your Name",
        "WHISSLE_LOCATION": "Your City"
      }
    }
  }
}
```

**Cursor** — `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/whissle-claude/venv/bin/python",
      "args": ["/path/to/whissle-claude/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here"
      }
    }
  }
}
```

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "command": "python",
      "args": ["/path/to/whissle-claude/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here"
      }
    }
  }
}
```

## Voice Dictation (claude-voice)

Press **Alt+V** to start recording, speak your prompt, press **Alt+V** again to stop. Speech is transcribed in real-time and injected into Claude Code — along with voice metadata (emotion, intent, speech rate, speaker identity) that Claude uses for better planning.

### How it works

```
┌──────────────────────────────────────────────────────────┐
│  claude-voice (PTY wrapper)                              │
│                                                          │
│  stdin ──┬──> claude (with --append-system-prompt)       │
│          │       ↕ reads .claude-voice/context.md        │
│          │                                               │
│          ├─ Alt+V > sox (mic) > Whissle ASR (WebSocket)  │
│          │                        │                      │
│          │         speaker ID <───┤ (cosine similarity)  │
│          │         emotion    <───┤                      │
│          │         intent     <───┘                      │
│          │                                               │
│          └─ Enter > text classifier (intent/emotion)     │
│                                                          │
│  Both voice and text > SessionContextStore               │
│                         > .claude-voice/context.md       │
│                         > inline <!-- voice: ... -->     │
└──────────────────────────────────────────────────────────┘
```

### Usage

```bash
# Basic — single user
claude-voice

# Collaborative — two speakers (pair programming)
claude-voice --speakers karan,reviewer

# Pass any Claude Code arguments through
claude-voice --model sonnet
claude-voice --continue
claude-voice -p "explain this codebase"
```

### Keyboard shortcuts

| Key | Action |
|---|---|
| **Alt+V** | Toggle voice recording on/off |
| All other keys | Passed through to Claude Code |

### Collaborative workflow

1. Start with `--speakers karan,reviewer` (or any names)
2. First person presses Alt+V, speaks, presses Alt+V to stop
3. Second person does the same — speaker change is auto-detected via voice embeddings
4. Both speakers' metadata is tracked independently
5. Typed text is also classified (intent/emotion) and attributed to the primary speaker
6. Claude reads `.claude-voice/context.md` for conversation dynamics

### What Claude sees

Claude receives a system prompt telling it about the voice session. It reads `.claude-voice/context.md` which contains:

- **Current state** — active speakers, last input, session mood
- **Speaker profiles** — per-speaker emotion trends, intent distribution, speech rate
- **Conversation dynamics** — agreement level, urgency, planning cues
- **Planning recommendations** — whether to ask, proceed, or present options
- **Recent inputs** — last 7 inputs with speaker labels and metadata

### Voice metadata

Both voice and typed input produce unified metadata:

- **Emotion** — HAPPY, ANGRY, SAD, NEUTRAL
- **Intent** — QUERY, COMMAND, INFORM
- **Speech rate** — words per minute, filler words, pauses (voice only)
- **Speaker** — auto-detected (voice) or primary speaker (text)

## Architecture

```
Claude Code / Cursor / Claude Desktop
    │                    │
    │  MCP protocol      │  PTY wrapper
    │  (stdio or SSE)    │  (claude-voice)
    ▼                    ▼
┌─────────────┐   ┌─────────────────┐
│ whissle-mcp │   │ Whissle ASR     │
│ (35+ tools) │   │ (WebSocket)     │
└──────┬──────┘   └────────┬────────┘
       │  HTTP             │  wss://
       ▼                   ▼
┌──────────────────────────────────┐
│  Whissle Gateway (api.whissle.ai)│
│  /agent/*   /asr/*   /backend/* │
└──────┬───────────────────────────┘
       │
  ┌────┴─────┬──────────┐
  ▼          ▼          ▼
Agent    Backend     ASR/TTS
(Gemini)  (Node.js)  (Whissle)
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `WHISSLE_API_TOKEN` | One of these | — | API token (`wh_...`) from lulu.whissle.ai/access |
| `WHISSLE_USER_ID` | required | — | Device/user ID from the Whissle app |
| `WHISSLE_AGENT_URL` | No | `https://api.whissle.ai/agent` | Agent service URL |
| `WHISSLE_BACKEND_URL` | No | Cloud Run backend | Node.js backend URL |
| `WHISSLE_USER_NAME` | No | — | Your name (for personalized responses) |
| `WHISSLE_LOCATION` | No | — | Default location for weather/places |
| `WHISSLE_ASR_URL` | No | `wss://api.whissle.ai/asr/stream` | ASR WebSocket endpoint |
| `WHISSLE_ASR_LANGUAGE` | No | `en` | Speech recognition language |
| `MCP_TRANSPORT` | No | `stdio` | MCP transport: `stdio` or `sse` |
| `PORT` | No | `8080` | Port for SSE transport |

## Prerequisites

| Requirement | Version | Component | Notes |
|---|---|---|---|
| **Python** | 3.11+ | MCP server | Virtual environment created by setup.sh |
| **Node.js** | 22+ | claude-voice | Native WebSocket support required |
| **sox** | any | claude-voice | Audio capture (`rec`/`sox` command) |
| **Claude Code CLI** | latest | claude-voice | Must be in PATH |
| **jq** | any | setup.sh | JSON config merging |
| **Whissle token** | — | both | Get one at lulu.whissle.ai/access |

## Project Structure

```
whissle-claude/
  server.py              # MCP server — 35+ tools (Python)
  pyproject.toml         # Python package config
  setup.sh               # Unified installer
  Dockerfile             # Cloud Run deployment (MCP only)
  claude-voice/          # Voice dictation sub-package (TypeScript)
    claude-voice          # Entrypoint script
    package.json
    src/
      index.ts            # PTY wrapper, Alt+V intercept
      mic.ts              # Microphone capture via sox
      asr-client.ts       # WebSocket client for Whissle ASR
      metadata.ts         # SessionContextStore — context.md generation
      speaker-tracker.ts  # Speaker identification via embeddings
      text-metadata.ts    # Text-based intent/emotion classification
```

## Deploy MCP to Cloud Run

```bash
gcloud builds submit --tag gcr.io/YOUR_PROJECT/whissle-mcp

gcloud run deploy whissle-mcp \
  --image gcr.io/YOUR_PROJECT/whissle-mcp \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --update-env-vars "MCP_TRANSPORT=sse,WHISSLE_AGENT_URL=https://api.whissle.ai/agent,WHISSLE_BACKEND_URL=https://live-assist-backend-843574834406.europe-west1.run.app"
```

## Troubleshooting

**`'claude' not found in PATH`** — Install Claude Code: `npm install -g @anthropic-ai/claude-code`

**`sox not found`** — Install sox: `brew install sox` (macOS) or `sudo apt install sox` (Linux)

**`Voice server connection failed`** — Check your token is valid and you have internet connectivity

**`Mic error`** — Ensure your microphone is connected and your terminal has microphone permissions (macOS: System Settings > Privacy & Security > Microphone)

**Module errors after Node.js upgrade** — Delete `node_modules` and reinstall: `cd claude-voice && rm -rf node_modules && npm install`

**Speaker detection not working** — Short utterances (<2 seconds) may not produce reliable speaker embeddings. Speak in longer phrases.

**MCP tools not appearing** — Restart your AI tool after running `./setup.sh`. Check the config file was written correctly.

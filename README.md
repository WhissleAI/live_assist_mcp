# whissle-claude

Personal AI context for [Claude Code](https://claude.ai/code). 35+ MCP tools + voice dictation — your calendar, email, memories, personality, web research, and more, all inside Claude.

Every interaction — typed or spoken — is analyzed for emotion, intent, and demographics, building a personality profile that makes Claude increasingly personalized over time.

## Install (one command)

```bash
git clone https://github.com/WhissleAI/whissle-claude.git
cd whissle-claude
./setup.sh
```

The installer will:
1. Check and install prerequisites (Node.js 22+, sox, Claude Code CLI, Python 3.11+, jq)
2. Prompt for your Whissle token (get one at [lulu.whissle.ai/access](https://lulu.whissle.ai/access))
3. Validate the token against the Whissle gateway
4. Save credentials to `~/.claude-voice/.env` (persisted across sessions)
5. Configure MCP for Claude Code, Cursor, and/or Claude Desktop
6. Optionally symlink `claude-voice` to your PATH

**That's it.** Restart Claude Code and all 35+ tools are available. Run `claude-voice` for voice input.

### Setup flags

```bash
./setup.sh                  # interactive — prompts for everything
./setup.sh --all            # configure all clients at once
./setup.sh --claude-code    # Claude Code only
./setup.sh --cursor         # Cursor only
./setup.sh --claude-desktop # Claude Desktop only
./setup.sh --mcp-only       # skip voice setup (no Node.js/sox needed)
./setup.sh --voice-only     # skip MCP server setup
```

## Usage

### MCP tools (text — works immediately after setup)

Just use Claude Code normally. The 35+ Whissle tools are available to Claude automatically:

```
> What's on my calendar today?          # Claude calls check_calendar
> Search my memories for the auth decision we made last week
> What's the weather in SF?
> Send an email to john@example.com summarizing today's standup
> Research best practices for WebSocket reconnection in 2026
```

Every text query you send through these tools is analyzed by the gateway for emotion, intent, and demographics — building your personality profile over time. You don't need to do anything special; it happens automatically.

### Voice (claude-voice)

```bash
claude-voice                              # basic — single user
claude-voice --speakers karan,reviewer    # collaborative — pair programming
claude-voice --model sonnet               # pass-through Claude flags
claude-voice --continue                   # resume last conversation
```

Press **Alt+V** to toggle recording. Speak your prompt. Press **Alt+V** to stop. Your speech is transcribed in real-time with emotion, intent, speech rate, and speaker identification — all injected into Claude's context.

### What gets analyzed

| Input type | Emotion | Intent | Demographics | Speech rate | Speaker ID |
|---|---|---|---|---|---|
| **Typed text** (MCP) | Yes | Yes | Yes | — | — |
| **Typed text** (claude-voice) | Yes | Yes | Yes | — | Primary speaker |
| **Voice** (claude-voice) | Yes (acoustic) | Yes (acoustic) | Yes | Yes | Yes (embeddings) |

All three input types feed the same personality pipeline. A user who only types builds their profile just as effectively as one who speaks.

## MCP Tools (35+)

| Category | Tools |
|---|---|
| **Core** | `ask_agent`, `deep_research`, `get_user_context`, `get_user_personality` |
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

## Voice: How It Works

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

### Collaborative workflow

1. Start with `--speakers karan,reviewer` (or any names)
2. Each person presses Alt+V, speaks, presses Alt+V to stop
3. Speaker change is auto-detected via voice embeddings (cosine similarity)
4. Both speakers' metadata is tracked independently
5. Claude reads `.claude-voice/context.md` for conversation dynamics — agreement level, urgency, and whether to ask, proceed, or present options

### Context file (`.claude-voice/context.md`)

Updated after every input. Contains:

- **Current state** — active speakers, last input mode, session mood
- **Speaker profiles** — per-speaker emotion trends, intent distribution, speech rate, filler word rate
- **Conversation dynamics** — agreement level, urgency, planning cues
- **Planning recommendations** — whether to ask a clarifying question, proceed with execution, or present options
- **Recent inputs** — last 7 inputs with speaker labels and metadata

## Architecture

```
                    You (typing or speaking)
                    │                    │
              ┌─────┘                    └─────┐
              ▼                                ▼
   ┌────────────────────┐          ┌───────────────────┐
   │  MCP Server        │          │  claude-voice      │
   │  (35+ tools)       │          │  (PTY + Alt+V mic) │
   │                    │          │                    │
   │  trigger_type:     │          │  ASR WebSocket     │
   │  "typed"           │          │  speaker tracking  │
   └────────┬───────────┘          └────────┬───────────┘
            │                               │
            ▼                               ▼
   ┌────────────────────────────────────────────────────┐
   │  Whissle Gateway (api.whissle.ai)                  │
   │                                                    │
   │  Text input:  regex + LLM metadata extraction      │
   │  Voice input: ASR acoustic metadata                │
   │                                                    │
   │  Both feed: personality, archetype, behavioral     │
   │  profile, RL bandit, conversation memory           │
   └────────┬───────────────────────────────────────────┘
            │
       ┌────┴─────┬──────────┐
       ▼          ▼          ▼
    Agent      Backend    ASR/TTS
   (Gemini)   (Node.js)  (Whissle)
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `WHISSLE_API_TOKEN` | One of | — | API token (`wh_...`) from lulu.whissle.ai/access |
| `WHISSLE_USER_ID` | these | — | Device/user ID from the Whissle app |
| `WHISSLE_USER_NAME` | No | — | Your name (personalized responses) |
| `WHISSLE_LOCATION` | No | — | Default location (weather/places) |
| `WHISSLE_ASR_URL` | No | `wss://api.whissle.ai/asr/stream` | ASR WebSocket endpoint |
| `WHISSLE_ASR_LANGUAGE` | No | `en` | Speech recognition language |
| `WHISSLE_AGENT_URL` | No | `https://api.whissle.ai/agent` | Agent service URL |
| `WHISSLE_BACKEND_URL` | No | Cloud Run backend | Node.js backend URL |
| `MCP_TRANSPORT` | No | `stdio` | MCP transport: `stdio` or `sse` |
| `PORT` | No | `8080` | Port for SSE transport |

## Manual MCP Setup

If you prefer not to use `./setup.sh`:

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

**Cursor** — `~/.cursor/mcp.json`:
```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/whissle-claude/venv/bin/python",
      "args": ["/path/to/whissle-claude/server.py"],
      "env": { "WHISSLE_API_TOKEN": "wh_your_token_here" }
    }
  }
}
```

**Cloud-hosted (SSE)** — for Cursor or Claude Desktop:
```json
{
  "mcpServers": {
    "whissle": {
      "url": "https://whissle-mcp-843574834406.us-central1.run.app/sse",
      "headers": { "X-User-Id": "YOUR_WHISSLE_USER_ID" }
    }
  }
}
```

## Project Structure

```
whissle-claude/
  server.py              # MCP server — 35+ tools, trigger_type + metadata passthrough
  pyproject.toml         # Python package config (whissle-mcp)
  setup.sh               # Unified installer (prereqs + credentials + MCP config + voice)
  Dockerfile             # Cloud Run deployment (MCP only)
  claude-voice/          # Voice dictation sub-package (TypeScript)
    claude-voice          # Entrypoint — loads token from ~/.claude-voice/.env
    package.json          # deps: node-pty, tsx, which
    src/
      index.ts            # PTY wrapper, Alt+V intercept, system prompt injection
      mic.ts              # Microphone capture via sox/rec (16kHz PCM)
      asr-client.ts       # WebSocket client for Whissle ASR streaming
      metadata.ts         # SessionContextStore — context.md generation + planning recommendations
      speaker-tracker.ts  # Multi-speaker identification via cosine similarity on embeddings
      text-metadata.ts    # Text-based intent/emotion classification (regex heuristics)
```

## Troubleshooting

**`'claude' not found in PATH`** — Install Claude Code: `npm install -g @anthropic-ai/claude-code`

**`sox not found`** — Install sox: `brew install sox` (macOS) or `sudo apt install sox` (Linux)

**`Voice server connection failed`** — Check your token is valid and you have internet connectivity

**`Mic error`** — Ensure your terminal has microphone permissions (macOS: System Settings > Privacy & Security > Microphone)

**Module errors** — `cd claude-voice && rm -rf node_modules && npm install`

**Speaker detection not working** — Short utterances (<2s) may not produce reliable embeddings. Speak in longer phrases.

**MCP tools not appearing** — Restart Claude Code after `./setup.sh`. Check `~/.claude/settings.json` has the `whissle` entry.

**Token expired** — Re-run `./setup.sh` to enter a new token. Or edit `~/.claude-voice/.env` directly.

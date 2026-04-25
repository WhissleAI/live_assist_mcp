# Whissle Live Assist — MCP Server

MCP (Model Context Protocol) server that connects **Claude Code, Cursor, and Claude Desktop** to the full Whissle AI gateway. Your coding assistant gets 35+ tools — memories, calendar, email, contacts, web search, research, code execution, Google Drive/Sheets/Tasks, finance, media analysis, navigation, and more.

## Quick Setup

```bash
cd live_assist_mcp
./setup.sh              # interactive — prompts for credentials + targets
./setup.sh --all        # all clients (Claude Code + Cursor + Claude Desktop)
./setup.sh --claude-code
./setup.sh --cursor
./setup.sh --claude-desktop
```

The script installs dependencies, collects your credentials, and writes the MCP config for each target.

## Available Tools (35+)

| Category | Tools |
|---|---|
| **Core Agent** | `ask_agent`, `deep_research`, `get_user_context` |
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

## Manual Setup

### Option A: Cloud-hosted (recommended)

The MCP server is deployed on Cloud Run. Just add the URL to your config.

**Cursor** — `.cursor/mcp.json` (or `~/.cursor/mcp.json` globally):

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

### Option B: Run locally (stdio)

```bash
cd live_assist_mcp
python -m venv venv && source venv/bin/activate
pip install -e .
```

**Claude Code** — `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/live_assist_mcp/venv/bin/python",
      "args": ["/path/to/live_assist_mcp/server.py"],
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
      "command": "/path/to/live_assist_mcp/venv/bin/python",
      "args": ["/path/to/live_assist_mcp/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here",
        "WHISSLE_USER_NAME": "Your Name",
        "WHISSLE_LOCATION": "Your City"
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
      "args": ["/path/to/live_assist_mcp/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here"
      }
    }
  }
}
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `WHISSLE_API_TOKEN` | One of these | — | API token (wh_...) from lulu.whissle.ai/access |
| `WHISSLE_USER_ID` | required | — | Device/user ID from the Whissle app |
| `WHISSLE_AGENT_URL` | No | `https://api.whissle.ai/agent` | Agent service URL |
| `WHISSLE_BACKEND_URL` | No | Cloud Run backend | Node.js backend URL |
| `WHISSLE_USER_NAME` | No | — | Your name (for personalized responses) |
| `WHISSLE_LOCATION` | No | — | Default location for weather/places |
| `MCP_TRANSPORT` | No | `stdio` | Transport: `stdio` or `sse` |
| `PORT` | No | `8080` | Port for SSE transport (Cloud Run sets this) |

## How It Works

```
Claude Code / Cursor / Claude Desktop
    │
    │  MCP protocol (stdio or SSE)
    ▼
┌─────────────────────────┐
│  whissle-mcp            │  ← this server (35+ tools)
│  (tools adapter)        │
└────────┬────────────────┘
         │  HTTP → api.whissle.ai
         ▼
┌─────────────────────────┐
│  Whissle Gateway        │  (Cloud Run, port 9000)
│  /agent/*               │
└────────┬────────────────┘
         │
    ┌────┴─────┬──────────┐
    ▼          ▼          ▼
  Agent    Backend     ASR/TTS
 (Gemini)  (Node.js)   (Whissle)
```

The MCP server is a thin stateless adapter — all state (memories, personality, calendar tokens) lives in the existing Whissle backend. Tools that would otherwise require Claude API tokens for reasoning (web search, research, code execution, document analysis) are routed through the Whissle agent which uses Gemini, reducing Claude API costs.

## Deploy to Cloud Run

```bash
gcloud builds submit --tag gcr.io/YOUR_PROJECT/whissle-mcp

gcloud run deploy whissle-mcp \
  --image gcr.io/YOUR_PROJECT/whissle-mcp \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --update-env-vars "MCP_TRANSPORT=sse,WHISSLE_AGENT_URL=https://api.whissle.ai/agent,WHISSLE_BACKEND_URL=https://live-assist-backend-843574834406.europe-west1.run.app"
```

# Whissle Live Assist — MCP Server

MCP (Model Context Protocol) server that connects Cursor, Claude Desktop, or any MCP-compatible AI assistant to your Whissle personal AI backend.

Your coding assistant gets access to your **memories, personality, calendar, email, weather, news, and deep research** — all personalized to you.

## Available Tools

| Tool | Description |
|---|---|
| `search_memories` | Search your stored memories for relevant context |
| `store_memory` | Save a decision, preference, or note to memory |
| `ask_agent` | Ask anything — auto-routes to the right capability |
| `deep_research` | Multi-source web research with citations |
| `check_calendar` | View upcoming Google Calendar events |
| `check_email` | Summarize recent Gmail inbox |
| `get_weather` | Current weather and forecast |
| `get_news` | Latest headlines |
| `daily_briefing` | Combined weather + calendar + news briefing |
| `get_user_context` | Your personality, archetype, and communication style |

## Setup

### Option A: Cloud-hosted (recommended)

The MCP server is deployed on Cloud Run. Just add the URL to your Cursor config.

**1. Add to Cursor** — create or edit `.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` globally):

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

**2. Restart Cursor** — the Whissle tools will appear in Cursor's tool list.

> Replace `YOUR_WHISSLE_USER_ID` with your device/user ID from the Whissle app.

### Option B: Run locally (stdio)

**1. Clone and install:**

```bash
cd live_assist_mcp
python -m venv venv && source venv/bin/activate
pip install -e .
```

**2. Add to Cursor** — `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/live_assist_mcp/venv/bin/python",
      "args": ["/path/to/live_assist_mcp/server.py"],
      "env": {
        "WHISSLE_USER_ID": "YOUR_WHISSLE_USER_ID",
        "WHISSLE_USER_NAME": "Karan",
        "WHISSLE_LOCATION": "San Francisco"
      }
    }
  }
}
```

**3. Restart Cursor.**

### Option C: Claude Desktop

Add to Claude Desktop's config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "whissle": {
      "command": "python",
      "args": ["/path/to/live_assist_mcp/server.py"],
      "env": {
        "WHISSLE_USER_ID": "YOUR_WHISSLE_USER_ID"
      }
    }
  }
}
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `WHISSLE_USER_ID` | Yes | — | Your device/user ID from the Whissle app |
| `WHISSLE_AGENT_URL` | No | Cloud Run gateway | Agent service URL |
| `WHISSLE_BACKEND_URL` | No | Cloud Run backend | Node.js backend URL |
| `WHISSLE_USER_NAME` | No | — | Your name (for personalized responses) |
| `WHISSLE_LOCATION` | No | — | Default location for weather |
| `MCP_TRANSPORT` | No | `stdio` | Transport: `stdio` or `sse` |
| `PORT` | No | `8080` | Port for SSE transport (Cloud Run sets this) |

## Deploy to Cloud Run

```bash
# Build and push
gcloud builds submit --tag gcr.io/YOUR_PROJECT/whissle-mcp

# Deploy
gcloud run deploy whissle-mcp \
  --image gcr.io/YOUR_PROJECT/whissle-mcp \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars "MCP_TRANSPORT=sse,WHISSLE_AGENT_URL=https://api.whissle.ai/agent,WHISSLE_BACKEND_URL=https://live-assist-backend-843574834406.europe-west1.run.app"
```

> Note: The Cloud Run deployment does NOT bake in a user ID — each user passes their own ID via the `X-User-Id` header in their Cursor config.

## How It Works

```
Cursor / Claude Desktop
    │
    │  MCP protocol (stdio or SSE)
    ▼
┌─────────────────────┐
│  whissle-mcp        │  ← this server
│  (tools adapter)    │
└────────┬────────────┘
         │  HTTP
         ▼
┌─────────────────────┐
│  Whissle Gateway    │  (Cloud Run, port 9000)
│  /agent/*           │
└────────┬────────────┘
         │
    ┌────┴─────┬──────────┐
    ▼          ▼          ▼
  Agent    Backend     ASR/TTS
 (8765)    (3001)     (8001)
```

The MCP server is a thin stateless adapter — all state (memories, personality, calendar tokens) lives in the existing Whissle backend.

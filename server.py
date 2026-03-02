"""
Whissle Live Assist — MCP Server for Cursor / Claude Desktop.

Exposes the Whissle agentic backend (memories, personality, research,
calendar, email, weather, briefing) as MCP tools so that any MCP-capable
AI coding assistant can leverage the user's personal context.

Requires one of:
  WHISSLE_USER_ID   — device ID (from browser.whissle.ai)
  WHISSLE_API_TOKEN — API token (wh_...) — resolves to device ID automatically

Optional:
  WHISSLE_AGENT_URL    — agent service URL (defaults to Cloud Run gateway)
  WHISSLE_BACKEND_URL  — Node.js backend URL (defaults to Cloud Run)
  WHISSLE_USER_NAME    — user's display name (for personalization)
  WHISSLE_LOCATION     — default location for weather
  MCP_TRANSPORT        — "stdio" (local, default) or "sse" (Cloud Run)
  PORT                 — port for SSE transport (Cloud Run sets this to 8080)
"""

import json
import logging
import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("whissle-mcp")

AGENT_URL = os.getenv(
    "WHISSLE_AGENT_URL",
    "https://api.whissle.ai/agent",
).rstrip("/")

BACKEND_URL = os.getenv(
    "WHISSLE_BACKEND_URL",
    "https://live-assist-backend-843574834406.europe-west1.run.app",
).rstrip("/")

USER_ID = os.getenv("WHISSLE_USER_ID", "")
API_TOKEN = os.getenv("WHISSLE_API_TOKEN", "").strip()
USER_NAME = os.getenv("WHISSLE_USER_NAME", "")
USER_LOCATION = os.getenv("WHISSLE_LOCATION", "")

TIMEOUT = httpx.Timeout(90, connect=10)

_transport = os.getenv("MCP_TRANSPORT", "stdio")
_port = int(os.getenv("PORT", "8080"))

# Resolved from API token at first use
_resolved_user_id: str | None = None


def _auth_headers() -> dict[str, str]:
    """Headers for API-token-authenticated requests."""
    if API_TOKEN and API_TOKEN.startswith("wh_"):
        return {"Authorization": f"Bearer {API_TOKEN}"}
    return {}


async def _resolve_user_id() -> str:
    """Resolve user ID from API token if needed."""
    global _resolved_user_id
    if USER_ID:
        return USER_ID
    if _resolved_user_id:
        return _resolved_user_id
    if not API_TOKEN or not API_TOKEN.startswith("wh_"):
        raise ValueError(
            "Set WHISSLE_USER_ID or WHISSLE_API_TOKEN in your MCP config. "
            "Get a token at browser.whissle.ai/access"
        )
    validate_url = f"{BACKEND_URL.rstrip('/')}/api-tokens/validate?token={API_TOKEN}"
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.get(validate_url)
        if r.status_code == 200:
            data = r.json()
            if data.get("valid") and data.get("deviceId"):
                _resolved_user_id = data["deviceId"]
                return _resolved_user_id
    raise ValueError("Invalid WHISSLE_API_TOKEN. Generate a new one at browser.whissle.ai/access")


async def _ensure_user_id() -> str:
    """Async helper to resolve user ID (for API token)."""
    if USER_ID:
        return USER_ID
    return await _resolve_user_id()


mcp = FastMCP(
    "Whissle Live Assist",
    instructions=(
        "Personal AI assistant with memories, personality, calendar, email, "
        "weather, news, research, and daily briefings — all personalized to you."
    ),
    host="0.0.0.0",
    port=_port,
)


async def _consume_sse(resp: httpx.Response) -> dict[str, Any]:
    """Consume an SSE stream from /route/stream and return assembled result."""
    chunks: list[str] = []
    metadata: dict[str, Any] = {}

    async for line in resp.aiter_lines():
        if not line.startswith("data: "):
            continue
        try:
            event = json.loads(line[6:])
        except json.JSONDecodeError:
            continue

        etype = event.get("event", "")
        if etype == "chunk":
            chunks.append(event.get("text", ""))
        elif etype == "done":
            if not chunks and event.get("summary"):
                chunks.append(event["summary"])
            metadata = event
        elif etype == "error":
            raise RuntimeError(event.get("message", "Agent error"))

    return {"text": "".join(chunks), **metadata}


async def _agent_stream(
    query: str,
    mode_hint: str = "",
    **extra: Any,
) -> str:
    """POST to /route/stream, consume SSE, return final text."""
    uid = await _ensure_user_id()
    body: dict[str, Any] = {
        "query": query,
        "user_id": uid,
        "user_name": USER_NAME,
        "location": USER_LOCATION,
    }
    if mode_hint:
        body["mode_hint"] = mode_hint
    body.update(extra)

    headers = {"Accept": "text/event-stream", **_auth_headers()}
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        async with client.stream(
            "POST",
            f"{AGENT_URL}/route/stream",
            json=body,
            headers=headers,
        ) as resp:
            resp.raise_for_status()
            result = await _consume_sse(resp)

    return result.get("text", "(no response)")


# ---------------------------------------------------------------------------
# MCP Tools
# ---------------------------------------------------------------------------

@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def search_memories(query: str) -> str:
    """Search your personal Whissle memories for context relevant to a query.

    Use this to recall past decisions, preferences, notes, or anything
    you've previously told the assistant.

    Args:
        query: What to search for in your memories (e.g. "database schema decision")
    """
    uid = await _ensure_user_id()
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(
            f"{AGENT_URL}/memory/search",
            json={"user_id": uid, "query": query, "limit": 12, "min_relevance": 0.1},
            headers=_auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()

    results = data.get("results", data.get("memories", []))
    if not results:
        return "No relevant memories found."

    lines = []
    for i, m in enumerate(results, 1):
        content = m.get("content", m) if isinstance(m, dict) else str(m)
        lines.append(f"{i}. {content}")
    return "\n".join(lines)


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=False))
async def store_memory(content: str, category: str = "general") -> str:
    """Store a piece of information to your Whissle memory for future recall.

    Use this to save decisions, preferences, important context, or anything
    you want the assistant to remember across sessions.

    Args:
        content: The information to remember (e.g. "Decided to use PostgreSQL for the main DB")
        category: Category tag — general, preference, decision, note, project
    """
    uid = await _ensure_user_id()
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(
            f"{AGENT_URL}/memory/store",
            json={
                "user_id": uid,
                "content": content,
                "category": category,
                "source": "cursor-mcp",
            },
            headers=_auth_headers(),
        )
        resp.raise_for_status()
    return f"Stored to memory ({category}): {content[:120]}"


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def ask_agent(query: str) -> str:
    """Ask the Whissle intelligent agent any question with your full personal context.

    The agent automatically detects intent and routes to chat, research, weather,
    calendar, email, news, or memories — with your personality and memories included.

    Args:
        query: Your question or request (e.g. "What should I focus on today?")
    """
    return await _agent_stream(query)


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def deep_research(query: str) -> str:
    """Run multi-source web research through the Whissle agent, personalized to you.

    Searches multiple sources, synthesizes findings, and returns a detailed report
    with citations. Your personality and preferences shape the output style.

    Args:
        query: Research topic (e.g. "Best practices for WebSocket reconnection in React 2025")
    """
    return await _agent_stream(query, mode_hint="deep")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def check_calendar(query: str = "what's on my calendar this week") -> str:
    """Check your Google Calendar for upcoming events and meetings.

    Args:
        query: Calendar question (e.g. "what meetings do I have tomorrow")
    """
    return await _agent_stream(query, mode_hint="calendar_query")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def check_email(query: str = "summarize my recent emails") -> str:
    """Check your Gmail inbox and get a summary of recent messages.

    Args:
        query: Email question (e.g. "any important emails today")
    """
    return await _agent_stream(query, mode_hint="email_query")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def get_weather(location: str = "") -> str:
    """Get current weather and forecast for a location (defaults to your home location).

    Args:
        location: City or location name (leave empty to use your default)
    """
    loc = location or USER_LOCATION
    q = f"weather in {loc}" if loc else "what's the weather"
    return await _agent_stream(q, mode_hint="weather", location=loc)


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def get_news(query: str = "top headlines today") -> str:
    """Get the latest news headlines.

    Args:
        query: News topic or "top headlines" for general news
    """
    return await _agent_stream(query, mode_hint="news")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def daily_briefing() -> str:
    """Get your personalized daily briefing — weather, calendar, and top news combined."""
    return await _agent_stream("daily briefing", mode_hint="briefing")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
async def get_user_context() -> str:
    """Retrieve your full Whissle profile: personality, archetype, communication style, and recent history.

    Use this when you need to understand the user's preferences or style before
    generating code, documentation, or responses.
    """
    uid = await _ensure_user_id()
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.get(
            f"{AGENT_URL}/conversation/context/{uid}",
            headers=_auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()

    parts: list[str] = []
    if data.get("personality"):
        parts.append(f"Personality:\n{data['personality']}")
    if data.get("archetype"):
        arch = data["archetype"]
        if isinstance(arch, dict) and arch.get("style_prompt"):
            parts.append(f"Communication style:\n{arch['style_prompt']}")
        elif isinstance(arch, str):
            parts.append(f"Communication style:\n{arch}")
    if data.get("recent_history"):
        history_lines = []
        for item in data["recent_history"][:5]:
            if isinstance(item, dict):
                mode = item.get("mode", "")
                text = (item.get("processed_text") or item.get("transcript", ""))[:120]
                history_lines.append(f"  [{mode}] {text}")
        if history_lines:
            parts.append("Recent interactions:\n" + "\n".join(history_lines))
    if data.get("notes"):
        notes = data["notes"]
        note_lines = [f"  - {n[:150]}" for n in (notes if isinstance(notes, list) else [notes])[:3]]
        parts.append("Notes:\n" + "\n".join(note_lines))

    return "\n\n".join(parts) if parts else "No user context available."


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport=_transport)

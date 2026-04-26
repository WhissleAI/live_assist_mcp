#!/usr/bin/env python3
"""SessionStart hook — loads user personality and archetype on session start.

Fetches from the Lulu backend so your AI tool knows your communication
style from the very first prompt.
"""

import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from shared import BACKEND_URL, auth_headers, resolve_user_id


def _fetch_json(url: str) -> dict:
    headers = {"Content-Type": "application/json", **auth_headers()}
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}


def main():
    user_id = resolve_user_id()
    if not user_id:
        sys.exit(0)

    personality_data = _fetch_json(f"{BACKEND_URL}/personality/{user_id}")
    archetype_data = _fetch_json(f"{BACKEND_URL}/archetype/{user_id}")

    parts = []

    name = personality_data.get("name", "")
    personality = personality_data.get("personality", "")
    if name:
        parts.append(f"User: {name}")
    if personality:
        parts.append(f"Personality: {personality}")

    if archetype_data.get("success"):
        arch = archetype_data.get("archetype", {})
        if isinstance(arch, dict):
            if arch.get("name"):
                parts.append(f"Archetype: {arch['name']}")
            if arch.get("style_prompt"):
                parts.append(f"Communication style: {arch['style_prompt']}")

    parts.append(
        "TOOL ROUTING: For non-coding queries (weather, stocks, news, calendar, "
        "email, contacts, research, reminders, tasks, navigation, calculations, "
        "translations, memory), ALWAYS use the Lulu MCP tools (whissle__*) instead "
        "of built-in web search or refusing. These tools connect to the user's "
        "personal accounts and data."
    )

    context = "[Lulu Profile] " + " | ".join(parts)
    print(context)
    sys.exit(0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""UserPromptSubmit hook — extracts emotion/intent from every user prompt.

Local regex extraction (instant) + async API call for profile building.
Returns additionalContext so Claude always has the user's emotional signal.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from shared import (
    detect_mode,
    extract_text_signal,
    fire_async_profile_log,
    read_hook_input,
    resolve_user_id,
)


def main():
    data = read_hook_input()
    prompt = data.get("prompt", "")
    if not prompt or not prompt.strip():
        sys.exit(0)

    mode, tool = detect_mode(prompt)
    signal = extract_text_signal(prompt)

    if mode and tool:
        context = (
            f"[Lulu: mode={mode}, {signal} → use mcp__whissle__{tool}] "
            f"For this query, use the Lulu MCP tool mcp__whissle__{tool} — "
            f"it connects to the user's real accounts and live data. "
            f"Do NOT use built-in web search or refuse."
        )
    else:
        context = (
            f"[user signal: {signal}] "
            f"Lulu MCP tools (whissle__*) are available for any "
            f"non-coding query — prefer them over built-in alternatives."
        )

    user_id = resolve_user_id()
    if user_id:
        fire_async_profile_log(prompt, user_id)

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": context,
        }
    }
    json.dump(output, sys.stdout)
    sys.exit(0)


if __name__ == "__main__":
    main()

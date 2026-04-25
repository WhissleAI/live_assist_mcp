#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Whissle MCP — One-command setup for Claude Code, Cursor, and Claude Desktop
#
# Usage:
#   ./setup.sh                  # interactive — prompts for credentials + targets
#   ./setup.sh --all            # install for all supported clients
#   ./setup.sh --claude-code    # Claude Code only
#   ./setup.sh --cursor         # Cursor only
#   ./setup.sh --claude-desktop # Claude Desktop only
#
# Environment variables (skip prompts):
#   WHISSLE_USER_ID, WHISSLE_API_TOKEN, WHISSLE_USER_NAME, WHISSLE_LOCATION
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
PYTHON="${VENV_DIR}/bin/python"
SERVER_PY="$SCRIPT_DIR/server.py"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

# ── Parse flags ──────────────────────────────────────────────────────────────
DO_CLAUDE_CODE=false
DO_CURSOR=false
DO_CLAUDE_DESKTOP=false
INTERACTIVE=true

for arg in "$@"; do
  case "$arg" in
    --all)            DO_CLAUDE_CODE=true; DO_CURSOR=true; DO_CLAUDE_DESKTOP=true; INTERACTIVE=false ;;
    --claude-code)    DO_CLAUDE_CODE=true; INTERACTIVE=false ;;
    --cursor)         DO_CURSOR=true; INTERACTIVE=false ;;
    --claude-desktop) DO_CLAUDE_DESKTOP=true; INTERACTIVE=false ;;
    --help|-h)
      echo "Usage: ./setup.sh [--all | --claude-code | --cursor | --claude-desktop]"
      echo ""
      echo "Sets up the Whissle MCP server for your AI coding tools."
      echo "Without flags, runs interactively."
      exit 0 ;;
  esac
done

# ── Step 1: Python venv + dependencies ───────────────────────────────────────
echo ""
echo -e "${BOLD}Whissle MCP Setup${NC}"
echo "──────────────────────────────────────"
echo ""

if [ ! -f "$PYTHON" ]; then
  info "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

info "Installing dependencies..."
"$VENV_DIR/bin/pip" install -q -e "$SCRIPT_DIR" 2>/dev/null
ok "Dependencies installed"

# ── Step 2: Collect credentials ──────────────────────────────────────────────

if [ -z "${WHISSLE_API_TOKEN:-}" ] && [ -z "${WHISSLE_USER_ID:-}" ]; then
  echo ""
  info "Credentials (get a token at lulu.whissle.ai/access)"
  echo -n "  API token (wh_...) or user ID: "
  read -r CRED_INPUT
  if [[ "$CRED_INPUT" == wh_* ]]; then
    WHISSLE_API_TOKEN="$CRED_INPUT"
    WHISSLE_USER_ID=""
  else
    WHISSLE_USER_ID="$CRED_INPUT"
    WHISSLE_API_TOKEN=""
  fi
fi

if [ -z "${WHISSLE_USER_NAME:-}" ]; then
  echo -n "  Your name (for personalization, enter to skip): "
  read -r WHISSLE_USER_NAME
fi

if [ -z "${WHISSLE_LOCATION:-}" ]; then
  echo -n "  Default location (e.g. San Francisco, enter to skip): "
  read -r WHISSLE_LOCATION
fi

echo ""

# ── Step 3: Choose targets (interactive) ─────────────────────────────────────

if $INTERACTIVE; then
  echo "Which tools to configure?"
  echo "  1) Claude Code"
  echo "  2) Cursor"
  echo "  3) Claude Desktop"
  echo "  4) All of the above"
  echo -n "  Choice [1-4, default=4]: "
  read -r CHOICE
  case "${CHOICE:-4}" in
    1) DO_CLAUDE_CODE=true ;;
    2) DO_CURSOR=true ;;
    3) DO_CLAUDE_DESKTOP=true ;;
    4) DO_CLAUDE_CODE=true; DO_CURSOR=true; DO_CLAUDE_DESKTOP=true ;;
    *) err "Invalid choice"; exit 1 ;;
  esac
  echo ""
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

build_env_json() {
  local env="{"
  local first=true
  if [ -n "${WHISSLE_API_TOKEN:-}" ]; then
    env+="\"WHISSLE_API_TOKEN\":\"$WHISSLE_API_TOKEN\""
    first=false
  elif [ -n "${WHISSLE_USER_ID:-}" ]; then
    env+="\"WHISSLE_USER_ID\":\"$WHISSLE_USER_ID\""
    first=false
  fi
  if [ -n "${WHISSLE_USER_NAME:-}" ]; then
    $first || env+=","
    env+="\"WHISSLE_USER_NAME\":\"$WHISSLE_USER_NAME\""
    first=false
  fi
  if [ -n "${WHISSLE_LOCATION:-}" ]; then
    $first || env+=","
    env+="\"WHISSLE_LOCATION\":\"$WHISSLE_LOCATION\""
  fi
  env+="}"
  echo "$env"
}

ENV_JSON=$(build_env_json)

ensure_jq() {
  if ! command -v jq &>/dev/null; then
    err "jq is required for JSON config updates. Install it: brew install jq"
    exit 1
  fi
}

# Merge an MCP server entry into a JSON config file.
# Usage: upsert_mcp_config <file> <server_name> <server_json>
upsert_mcp_config() {
  local file="$1" name="$2" server_json="$3"
  ensure_jq

  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    echo '{}' > "$file"
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg name "$name" --argjson srv "$server_json" \
    '.mcpServers[$name] = $srv' "$file" > "$tmp" && mv "$tmp" "$file"
}

MCP_SERVER_JSON=$(cat <<ENDJSON
{
  "command": "$PYTHON",
  "args": ["$SERVER_PY"],
  "env": $ENV_JSON
}
ENDJSON
)

# ── Step 4: Configure targets ────────────────────────────────────────────────

if $DO_CLAUDE_CODE; then
  info "Configuring Claude Code..."
  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"

  if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo '{}' > "$CLAUDE_SETTINGS"
  fi

  ensure_jq
  tmp=$(mktemp)
  jq --argjson srv "$MCP_SERVER_JSON" \
    '.mcpServers.whissle = $srv' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  ok "Claude Code configured ($CLAUDE_SETTINGS)"
fi

if $DO_CURSOR; then
  info "Configuring Cursor (global)..."
  CURSOR_GLOBAL="$HOME/.cursor/mcp.json"
  upsert_mcp_config "$CURSOR_GLOBAL" "whissle" "$MCP_SERVER_JSON"
  ok "Cursor configured ($CURSOR_GLOBAL)"
fi

if $DO_CLAUDE_DESKTOP; then
  info "Configuring Claude Desktop..."
  if [[ "$OSTYPE" == darwin* ]]; then
    DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  else
    DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
  fi
  upsert_mcp_config "$DESKTOP_CONFIG" "whissle" "$MCP_SERVER_JSON"
  ok "Claude Desktop configured ($DESKTOP_CONFIG)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "Available tools (35+):"
echo "  Core:       ask_agent, deep_research, get_user_context"
echo "  Memory:     search_memories, store_memory"
echo "  Calendar:   check_calendar, create_calendar_event, set_reminder"
echo "  Email:      check_email, send_email"
echo "  Contacts:   search_contacts"
echo "  Drive:      search_drive, save_to_sheet, read_from_sheet"
echo "  Tasks:      create_task, list_tasks, complete_task"
echo "  Search:     web_search, read_url, fetch_news, get_news"
echo "  Finance:    get_stock_price, get_crypto_price, convert_currency"
echo "  Media:      search_videos, generate_image, analyze_image, analyze_audio, analyze_video"
echo "  Utilities:  translate_text, calculate, run_code, analyze_document, extract_text_metadata"
echo "  Navigation: search_places, get_directions"
echo "  Weather:    get_weather, daily_briefing"
echo "  Scheduling: schedule_recurring, list_scheduled_tasks, cancel_scheduled_task"
echo "  Settings:   set_preference"
echo ""
echo "Restart your AI tool to pick up the new configuration."

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Whissle — Unified setup for MCP server + claude-voice
#
# Usage:
#   ./setup.sh                  # interactive — prompts for everything
#   ./setup.sh --all            # install for all supported clients
#   ./setup.sh --claude-code    # Claude Code only
#   ./setup.sh --cursor         # Cursor only
#   ./setup.sh --claude-desktop # Claude Desktop only
#   ./setup.sh --mcp-only       # skip voice prerequisites + install
#   ./setup.sh --voice-only     # skip MCP server installation
#
# Environment variables (skip prompts):
#   WHISSLE_API_TOKEN, WHISSLE_USER_ID, WHISSLE_USER_NAME, WHISSLE_LOCATION
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
PYTHON="${VENV_DIR}/bin/python"
SERVER_PY="$SCRIPT_DIR/server.py"
VOICE_DIR="$SCRIPT_DIR/claude-voice"
TOKEN_DIR="$HOME/.claude-voice"
TOKEN_FILE="$TOKEN_DIR/.env"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}*${NC} $*"; }
ok()    { echo -e "${GREEN}+${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
err()   { echo -e "${RED}x${NC} $*" >&2; }

# ── Parse flags ──────────────────────────────────────────────────────────────
DO_CLAUDE_CODE=false
DO_CURSOR=false
DO_CLAUDE_DESKTOP=false
INTERACTIVE=true
SKIP_VOICE=false
SKIP_MCP=false

for arg in "$@"; do
  case "$arg" in
    --all)            DO_CLAUDE_CODE=true; DO_CURSOR=true; DO_CLAUDE_DESKTOP=true; INTERACTIVE=false ;;
    --claude-code)    DO_CLAUDE_CODE=true; INTERACTIVE=false ;;
    --cursor)         DO_CURSOR=true; INTERACTIVE=false ;;
    --claude-desktop) DO_CLAUDE_DESKTOP=true; INTERACTIVE=false ;;
    --mcp-only)       SKIP_VOICE=true ;;
    --voice-only)     SKIP_MCP=true ;;
    --help|-h)
      echo "Usage: ./setup.sh [flags]"
      echo ""
      echo "Flags:"
      echo "  --all              Install for all supported clients"
      echo "  --claude-code      Claude Code only"
      echo "  --cursor           Cursor only"
      echo "  --claude-desktop   Claude Desktop only"
      echo "  --mcp-only         Skip voice (claude-voice) setup"
      echo "  --voice-only       Skip MCP server setup"
      echo ""
      echo "Sets up the Whissle MCP server (35+ tools) and claude-voice"
      echo "(Alt+V voice dictation) for your AI coding tools."
      exit 0 ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Whissle Setup${NC}"
echo "=============================="
echo ""

# ── Detect OS ────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PKG_MGR="brew" ;;
  Linux)  PKG_MGR="apt" ;;
  *)      err "Unsupported OS: $OS"; exit 1 ;;
esac

# ── Voice prerequisites ─────────────────────────────────────────────────────
if ! $SKIP_VOICE; then
  echo -e "${BOLD}1. Prerequisites${NC}"
  echo ""

  # Node.js 22+
  if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 22 ]; then
      ok "Node.js $(node -v)"
    else
      err "Node.js $(node -v) found but v22+ is required (native WebSocket)"
      echo "    Install: https://nodejs.org or 'nvm install 22'"
      exit 1
    fi
  else
    err "Node.js not found"
    echo "    Install v22+ from https://nodejs.org or:"
    echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
    echo "    nvm install 22"
    exit 1
  fi

  # sox
  if command -v rec &>/dev/null || command -v sox &>/dev/null; then
    ok "sox ($(which rec 2>/dev/null || which sox))"
  else
    warn "sox not found — required for microphone capture"
    if [ "$PKG_MGR" = "brew" ]; then
      echo -n "    Install via Homebrew? [Y/n] "
      read -r answer
      if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
        warn "Skipping. Install manually: brew install sox"
      else
        brew install sox
        ok "sox installed"
      fi
    elif [ "$PKG_MGR" = "apt" ]; then
      echo -n "    Install via apt? [Y/n] "
      read -r answer
      if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
        warn "Skipping. Install manually: sudo apt install sox"
      else
        sudo apt install -y sox
        ok "sox installed"
      fi
    fi
  fi

  # Claude Code CLI
  if command -v claude &>/dev/null; then
    ok "Claude Code CLI ($(which claude))"
  else
    warn "Claude Code CLI not found"
    echo -n "    Install via npm? [Y/n] "
    read -r answer
    if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
      warn "Skipping. Install manually: npm install -g @anthropic-ai/claude-code"
    else
      npm install -g @anthropic-ai/claude-code
      ok "Claude Code CLI installed"
    fi
  fi

  echo ""
fi

# ── MCP server dependencies ─────────────────────────────────────────────────
if ! $SKIP_MCP; then
  echo -e "${BOLD}2. MCP Server${NC}"
  echo ""

  if [ ! -f "$PYTHON" ]; then
    info "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
  fi

  info "Installing Python dependencies..."
  "$VENV_DIR/bin/pip" install -q -e "$SCRIPT_DIR" 2>/dev/null
  ok "MCP server ready (35+ tools)"
  echo ""
fi

# ── Voice dependencies ──────────────────────────────────────────────────────
if ! $SKIP_VOICE; then
  echo -e "${BOLD}3. Voice (claude-voice)${NC}"
  echo ""

  info "Installing Node.js dependencies..."
  (cd "$VOICE_DIR" && npm install --silent 2>/dev/null)
  chmod +x "$VOICE_DIR/claude-voice"
  ok "claude-voice ready"
  echo ""
fi

# ── Collect credentials ─────────────────────────────────────────────────────
echo -e "${BOLD}4. Credentials${NC}"
echo ""

if [ -z "${WHISSLE_API_TOKEN:-}" ] && [ -z "${WHISSLE_USER_ID:-}" ]; then
  info "Get a token at lulu.whissle.ai/access"
  echo ""
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

# ── Validate token ──────────────────────────────────────────────────────────
if [ -n "${WHISSLE_API_TOKEN:-}" ] && [[ "$WHISSLE_API_TOKEN" == wh_* ]]; then
  info "Validating token..."
  VALIDATE_URL="https://live-assist-backend-843574834406.europe-west1.run.app/api-tokens/validate?token=$WHISSLE_API_TOKEN"
  HTTP_CODE=$(curl -s -o /tmp/whissle_validate.json -w "%{http_code}" "$VALIDATE_URL" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    VALID=$(python3 -c "import json; d=json.load(open('/tmp/whissle_validate.json')); print(d.get('valid',''))" 2>/dev/null || echo "")
    DEVICE_ID=$(python3 -c "import json; d=json.load(open('/tmp/whissle_validate.json')); print(d.get('deviceId',''))" 2>/dev/null || echo "")
    if [ "$VALID" = "True" ]; then
      ok "Token validated (device: ${DEVICE_ID:0:12}...)"
    else
      err "Token is invalid. Get a new one at lulu.whissle.ai/access"
      rm -f /tmp/whissle_validate.json
      exit 1
    fi
  else
    warn "Could not validate token (HTTP $HTTP_CODE). Continuing anyway..."
  fi
  rm -f /tmp/whissle_validate.json
fi

# ── Persist credentials ─────────────────────────────────────────────────────
mkdir -p "$TOKEN_DIR"
cat > "$TOKEN_FILE" <<EOF
# Whissle credentials — generated by setup.sh on $(date +%Y-%m-%d)
WHISSLE_API_TOKEN=${WHISSLE_API_TOKEN:-}
WHISSLE_USER_ID=${WHISSLE_USER_ID:-}
WHISSLE_USER_NAME=${WHISSLE_USER_NAME:-}
WHISSLE_LOCATION=${WHISSLE_LOCATION:-}
EOF
chmod 600 "$TOKEN_FILE"
ok "Credentials saved to $TOKEN_FILE"
echo ""

# ── Choose MCP targets ──────────────────────────────────────────────────────
if ! $SKIP_MCP; then
  if $INTERACTIVE; then
    echo -e "${BOLD}5. Configure MCP${NC}"
    echo ""
    echo "  Which tools to configure?"
    echo "    1) Claude Code"
    echo "    2) Cursor"
    echo "    3) Claude Desktop"
    echo "    4) All of the above"
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

  # ── Helpers ──────────────────────────────────────────────────────────────
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
      err "jq is required for JSON config updates."
      if [ "$PKG_MGR" = "brew" ]; then
        echo -n "    Install via Homebrew? [Y/n] "
        read -r answer
        if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
          err "Cannot continue without jq. Install: brew install jq"
          exit 1
        else
          brew install jq
          ok "jq installed"
        fi
      elif [ "$PKG_MGR" = "apt" ]; then
        echo -n "    Install via apt? [Y/n] "
        read -r answer
        if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
          err "Cannot continue without jq. Install: sudo apt install jq"
          exit 1
        else
          sudo apt install -y jq
          ok "jq installed"
        fi
      else
        err "Install jq manually and re-run."
        exit 1
      fi
    fi
  }

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

  # ── Configure targets ──────────────────────────────────────────────────
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
    info "Configuring Cursor..."
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
  # ── Configure hooks (Claude Code only) ──────────────────────────────────
  if $DO_CLAUDE_CODE; then
    info "Configuring Claude Code hooks..."
    HOOKS_DIR="$SCRIPT_DIR/hooks"
    chmod +x "$HOOKS_DIR/prompt-submit.py" "$HOOKS_DIR/session-start.py" 2>/dev/null || true

    HOOK_ENV="WHISSLE_API_TOKEN=${WHISSLE_API_TOKEN:-}"
    [ -n "${WHISSLE_USER_NAME:-}" ] && HOOK_ENV="$HOOK_ENV WHISSLE_USER_NAME=$WHISSLE_USER_NAME"
    [ -n "${WHISSLE_LOCATION:-}" ] && HOOK_ENV="$HOOK_ENV WHISSLE_LOCATION=$WHISSLE_LOCATION"

    PROMPT_HOOK_CMD="$HOOK_ENV $PYTHON $HOOKS_DIR/prompt-submit.py"
    SESSION_HOOK_CMD="$HOOK_ENV $PYTHON $HOOKS_DIR/session-start.py"

    python3 -c "
import json, os

settings_path = os.path.expanduser('$CLAUDE_SETTINGS')
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hooks = settings.setdefault('hooks', {})
hooks['UserPromptSubmit'] = [{'hooks': [{'type': 'command', 'command': '''$PROMPT_HOOK_CMD'''}]}]
hooks['SessionStart'] = [{'hooks': [{'type': 'command', 'command': '''$SESSION_HOOK_CMD'''}]}]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
"
    ok "Hooks configured (emotion/intent on every prompt, personality on session start)"
  fi

  echo ""
fi

# ── Make claude-voice globally accessible ────────────────────────────────────
if ! $SKIP_VOICE; then
  VOICE_BIN="$VOICE_DIR/claude-voice"
  echo -e "${BOLD}6. Global Access${NC}"
  echo ""
  echo "  Make 'claude-voice' available from anywhere?"
  echo "    1) Symlink to /usr/local/bin (may need sudo)"
  echo "    2) Symlink to ~/.local/bin"
  echo "    3) Skip (run from $VOICE_BIN)"
  echo -n "  Choice [1-3, default=3]: "
  read -r LINK_CHOICE
  case "${LINK_CHOICE:-3}" in
    1)
      sudo ln -sf "$VOICE_BIN" /usr/local/bin/claude-voice
      ok "claude-voice linked to /usr/local/bin/claude-voice"
      ;;
    2)
      mkdir -p "$HOME/.local/bin"
      ln -sf "$VOICE_BIN" "$HOME/.local/bin/claude-voice"
      ok "claude-voice linked to ~/.local/bin/claude-voice"
      if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        warn "~/.local/bin is not in your PATH. Add to your shell profile:"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      fi
      ;;
    3)
      info "Skipping symlink. Run directly: $VOICE_BIN"
      ;;
  esac
  echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""

if ! $SKIP_MCP; then
  echo "  MCP Server (35+ tools):"
  echo "    Core, Memory, Calendar, Email, Contacts, Drive, Tasks,"
  echo "    Web Search, Finance, Media, Utilities, Navigation, Weather"
  echo ""
  if $DO_CLAUDE_CODE; then
    echo "  Hooks (Claude Code):"
    echo "    SessionStart  — loads your personality + archetype on every session"
    echo "    PromptSubmit  — extracts emotion/intent from every typed prompt"
    echo ""
  fi
  echo "    Restart your AI tool to pick up the new configuration."
  echo ""
fi

if ! $SKIP_VOICE; then
  echo "  Voice Dictation (claude-voice):"
  echo "    Run:  claude-voice"
  echo "    Keys: Alt+V to toggle recording"
  echo "    Pair: claude-voice --speakers alice,bob"
  echo ""
fi

echo "  Credentials: $TOKEN_FILE"
echo ""

#!/usr/bin/env bash
# install.sh — video-director environment provisioner
# Idempotent. Prompts before each major action. DO NOT RUN AUTOMATICALLY.
#
# What it does:
#   1. Provisions ~/.video-director-venv (Python 3.11) if not present
#   2. Installs backgroundremover into that venv  (never system 3.14)
#   3. Installs opentimelineio into that venv
#   4. Registers obs-mcp at user scope (requires OBS WebSocket enabled)
#
# What it explicitly does NOT do:
#   • Install Stable Video Diffusion / AnimateDiff (CUDA-preferred, MPS fragile — deferred)
#   • Overwrite raw/ footage or any project edit/ dirs
#   • Write to system Python 3.14
#
# Usage: bash install.sh [--yes-all]
#   --yes-all  skip individual confirmations (use with care)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

VENV_DIR="${VENV_DIR:-$HOME/.video-director-venv}"
PYTHON311="${PYTHON311:-python3.11}"
YES_ALL=0

for arg in "$@"; do
  case "$arg" in
    --yes-all) YES_ALL=1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

log()  { echo -e "${BOLD}▶${RESET} $*"; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
fail() { echo -e "${RED}✗${RESET} $*"; }

confirm() {
  # confirm "message"; returns 0 for yes, 1 for no/skip
  local msg="$1"
  if [[ "$YES_ALL" -eq 1 ]]; then
    echo -e "${YELLOW}(--yes-all)${RESET} $msg"
    return 0
  fi
  echo ""
  echo -e "${BOLD}$msg${RESET}"
  read -r -p "  Proceed? [y/N] " answer
  case "$answer" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) warn "Skipped."; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      video-director — install.sh (idempotent)         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Skill dir : $SKILL_DIR"
echo -e "  Venv dir  : $VENV_DIR"
echo ""

# Check python3.11 exists
if ! command -v "$PYTHON311" &>/dev/null; then
  fail "python3.11 not found on PATH (tried: $PYTHON311)"
  echo "  Install via: brew install python@3.11"
  echo "  Then re-run this script."
  exit 1
fi

PYTHON311_VER=$("$PYTHON311" --version 2>&1)
ok "Found $PYTHON311_VER at $(command -v "$PYTHON311")"

# Verify it's actually 3.11, not accidentally something else
if ! echo "$PYTHON311_VER" | grep -q "Python 3\.11"; then
  fail "Expected Python 3.11 but got: $PYTHON311_VER — check PYTHON311 env var."
  exit 1
fi

# ---------------------------------------------------------------------------
# STEP 1 — Python 3.11 venv
# ---------------------------------------------------------------------------
if [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/python" ]]; then
  EXISTING_VER=$("$VENV_DIR/bin/python" --version 2>&1)
  ok "Venv already exists: $VENV_DIR ($EXISTING_VER)"
  VENV_CREATED=0
else
  if confirm "STEP 1: Create Python 3.11 venv at $VENV_DIR"; then
    log "Creating venv…"
    "$PYTHON311" -m venv "$VENV_DIR"
    ok "Venv created: $("$VENV_DIR/bin/python" --version)"
    VENV_CREATED=1
  else
    warn "Venv creation skipped — downstream steps may fail."
    VENV_CREATED=0
  fi
fi

# Convenience: pip inside the venv
VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

# ---------------------------------------------------------------------------
# STEP 2 — Upgrade pip in venv (idempotent)
# ---------------------------------------------------------------------------
if [[ -f "$VENV_PIP" ]]; then
  if confirm "STEP 2: Upgrade pip in venv (recommended; ensures modern resolver)"; then
    log "Upgrading pip…"
    "$VENV_PIP" install --upgrade pip --quiet
    ok "pip upgraded: $("$VENV_PIP" --version)"
  fi
fi

# ---------------------------------------------------------------------------
# STEP 3 — backgroundremover
# ---------------------------------------------------------------------------
BGREMOVER_INSTALLED=0
if [[ -f "$VENV_PYTHON" ]]; then
  if "$VENV_PYTHON" -c "import backgroundremover" &>/dev/null 2>&1 || \
     [[ -f "$VENV_DIR/bin/backgroundremover" ]]; then
    ok "backgroundremover already installed in venv."
    BGREMOVER_INSTALLED=1
  fi
fi

if [[ "$BGREMOVER_INSTALLED" -eq 0 ]]; then
  if [[ -f "$VENV_PIP" ]]; then
    echo ""
    echo -e "  ${YELLOW}Note:${RESET} backgroundremover pulls in torch (~2 GB on first install)."
    echo "  On Apple Silicon (arm64) this uses the MPS-capable CPU-fallback wheel."
    echo "  Installation can take 5–10 minutes on slow connections."
    if confirm "STEP 3: Install backgroundremover into venv (video bg-removal, PRE phase)"; then
      log "Installing backgroundremover…"
      # Install backgroundremover; onnxruntime is the lighter backend on arm64
      # Use --no-deps + explicit deps if the full wheel fails, but try the standard install first
      if "$VENV_PIP" install backgroundremover --quiet; then
        ok "backgroundremover installed."
      else
        warn "Standard install failed. Trying with --extra-index-url for arm64 wheels…"
        "$VENV_PIP" install backgroundremover \
          --extra-index-url https://download.pytorch.org/whl/cpu
        ok "backgroundremover installed (CPU wheels)."
      fi
    fi
  else
    warn "STEP 3 skipped — venv not ready."
  fi
fi

# ---------------------------------------------------------------------------
# STEP 4 — opentimelineio
# ---------------------------------------------------------------------------
OTIO_INSTALLED=0
if [[ -f "$VENV_PYTHON" ]]; then
  if "$VENV_PYTHON" -c "import opentimelineio" &>/dev/null 2>&1; then
    ok "opentimelineio already installed in venv."
    OTIO_INSTALLED=1
  fi
fi

if [[ "$OTIO_INSTALLED" -eq 0 ]]; then
  if [[ -f "$VENV_PIP" ]]; then
    if confirm "STEP 4: Install opentimelineio into venv (OTIO→FCPXML export, Phase 5)"; then
      log "Installing opentimelineio…"
      "$VENV_PIP" install opentimelineio --quiet
      ok "opentimelineio installed."
    fi
  else
    warn "STEP 4 skipped — venv not ready."
  fi
fi

# ---------------------------------------------------------------------------
# STEP 5 — obs-mcp (user scope)
# ---------------------------------------------------------------------------
echo ""
echo -e "  ${BOLD}OBS pre-requisite:${RESET} before registering obs-mcp, enable OBS WebSocket:"
echo "    OBS → Tools → WebSocket Server Settings → Enable WebSocket server"
echo "    Note the port (default 4455) and password."
echo ""

if ! command -v claude &>/dev/null; then
  warn "STEP 5 SKIPPED — 'claude' CLI not found. Install Claude Code first."
else
  # Check if already registered
  EXISTING=$(claude mcp list 2>/dev/null | grep -i "obs" | head -1 || echo "")
  if [[ -n "$EXISTING" ]]; then
    ok "obs-mcp already registered: $EXISTING"
  else
    if confirm "STEP 5: Register obs-mcp at user scope (requires OBS WebSocket already enabled)"; then
      log "Registering obs-mcp…"
      claude mcp add --scope user --transport stdio obs -- npx -y obs-mcp
      ok "obs-mcp registered. Verify with: claude mcp list"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# DEFERRED — Stable Video Diffusion / AnimateDiff
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}${BOLD}DEFERRED (not installed):${RESET}"
echo "  • Stable Video Diffusion — CUDA-preferred, fragile on Apple Silicon MPS."
echo "  • AnimateDiff            — same constraint."
echo "  These are tagged ⚠ in references/pipelines.md and excluded from v1."
echo ""

# ---------------------------------------------------------------------------
# Final check
# ---------------------------------------------------------------------------
echo -e "${BOLD}── Post-install verification ──────────────────────────${RESET}"
echo ""
log "Running doctor.sh…"
bash "$SCRIPT_DIR/doctor.sh" || true
echo ""
echo -e "${BOLD}install.sh complete.${RESET}"
echo "  If anything is still red, re-run the relevant step or check brew/pip output above."
echo ""

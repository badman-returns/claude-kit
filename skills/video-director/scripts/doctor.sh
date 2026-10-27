#!/usr/bin/env bash
# doctor.sh — video-director environment readiness report
# Prints a readiness table: tools present/missing, Python 3.11 venv health,
# ffmpeg-filter checks, obs-mcp registration.
# MUST NEVER CRASH on missing tools.
# Compatible with bash 3.2+ (macOS system bash).
#
# Usage: bash doctor.sh [--json]
#   --json  emit compact JSON instead of human table

# Do NOT use set -e here — the whole point is graceful handling of missing tools
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="${VENV_DIR:-$HOME/.video-director-venv}"
JSON_MODE=0

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helper: safe command existence + first-line version
# ---------------------------------------------------------------------------
cmd_exists() { command -v "$1" &>/dev/null; }

cmd_version() {
  # cmd_version <cmd> [vflag]
  local cmd="$1" vflag="${2:---version}"
  if cmd_exists "$cmd"; then
    "$cmd" $vflag 2>&1 | head -1 || echo "(no output)"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# SECTION 1: Core CLI tools
# Parallel arrays: TOOL_NAMES / TOOL_STATUS / TOOL_VERS
# (bash 3 compatible — no declare -A)
# ---------------------------------------------------------------------------
TOOL_NAMES=(ffmpeg ffprobe node python3.11 python3 brew pipx yt-dlp npx)
TOOL_STATUS=()
TOOL_VERS=()

for t in "${TOOL_NAMES[@]}"; do
  if cmd_exists "$t"; then
    TOOL_STATUS+=("OK")
    v=$(cmd_version "$t")
    TOOL_VERS+=("$v")
  else
    TOOL_STATUS+=("MISSING")
    TOOL_VERS+=("")
  fi
done

# OBS: check CLI then /Applications/OBS.app
OBS_STATUS="MISSING"
OBS_VERS=""
if cmd_exists obs; then
  OBS_STATUS="OK"
  OBS_VERS=$(cmd_version obs)
elif [[ -d "/Applications/OBS.app" ]]; then
  OBS_STATUS="OK (app)"
  OBS_VERS="OBS.app at /Applications/OBS.app"
fi

# ---------------------------------------------------------------------------
# SECTION 2: Python 3.11 venv health
# ---------------------------------------------------------------------------
VENV_STATUS="MISSING"
VENV_PYTHON_VER=""
VENV_BGREMOVER="MISSING"
VENV_OTIO="MISSING"

if [[ -f "$VENV_DIR/bin/python" ]]; then
  VENV_PYTHON_VER=$("$VENV_DIR/bin/python" --version 2>&1 || echo "error")
  VENV_STATUS="OK"

  if "$VENV_DIR/bin/python" -c "import backgroundremover" &>/dev/null 2>&1 \
     || [[ -f "$VENV_DIR/bin/backgroundremover" ]]; then
    VENV_BGREMOVER="OK"
  fi

  if "$VENV_DIR/bin/python" -c "import opentimelineio" &>/dev/null 2>&1; then
    VENV_OTIO="OK"
  fi
else
  if cmd_exists python3.11; then
    VENV_STATUS="MISSING (run install.sh to create)"
  else
    VENV_STATUS="MISSING (python3.11 not found either — check brew)"
  fi
fi

# ---------------------------------------------------------------------------
# SECTION 3: ffmpeg filter checks
# Parallel arrays: FILT_NAMES / FILT_STATUS
# ---------------------------------------------------------------------------
FILT_NAMES=(crop scale zoompan vidstabdetect vidstabtransform loudnorm lut3d haldclut subtitles zscale)
FILT_LABELS=(
  "reframe (safe-crop to 9:16)"
  "resize / aspect conversion"
  "zoom-emphasis"
  "stabilize pass-1 (detect)"
  "stabilize pass-2 (transform)"
  "EBU R128 loudness normalization"
  "3D LUT color grading"
  "Hald CLUT color grading"
  "SRT/ASS subtitle burn-in"
  "HDR->SDR tonemap chain"
)
FILT_STATUS=()

if cmd_exists ffmpeg; then
  # Fetch filter list once
  FILTER_LIST=$(ffmpeg -filters 2>/dev/null || echo "")
  for f in "${FILT_NAMES[@]}"; do
    if echo "$FILTER_LIST" | grep -qE "[[:space:]]${f}[[:space:]]"; then
      FILT_STATUS+=("OK")
    else
      FILT_STATUS+=("MISSING")
    fi
  done
else
  for f in "${FILT_NAMES[@]}"; do
    FILT_STATUS+=("UNKNOWN (no ffmpeg)")
  done
fi

# Composite: vidstab 2-pass requires both detect + transform
VIDSTAB_DETECT_OK=0
VIDSTAB_XFORM_OK=0
for i in "${!FILT_NAMES[@]}"; do
  [[ "${FILT_NAMES[$i]}" == "vidstabdetect"    ]] && [[ "${FILT_STATUS[$i]}" == "OK" ]] && VIDSTAB_DETECT_OK=1
  [[ "${FILT_NAMES[$i]}" == "vidstabtransform" ]] && [[ "${FILT_STATUS[$i]}" == "OK" ]] && VIDSTAB_XFORM_OK=1
done
VIDSTAB2PASS="MISSING"
[[ $VIDSTAB_DETECT_OK -eq 1 && $VIDSTAB_XFORM_OK -eq 1 ]] && VIDSTAB2PASS="OK"

LOUDNORM_STATUS="MISSING"
for i in "${!FILT_NAMES[@]}"; do
  [[ "${FILT_NAMES[$i]}" == "loudnorm" ]] && LOUDNORM_STATUS="${FILT_STATUS[$i]}"
done
LOUDNORM2PASS="$LOUDNORM_STATUS"  # pass-counting handled by render.py, same binary

# ---------------------------------------------------------------------------
# SECTION 4: obs-mcp registration
# ---------------------------------------------------------------------------
OBS_MCP_STATUS="UNKNOWN"
if cmd_exists claude; then
  OBS_MCP_RAW=$(claude mcp list 2>/dev/null || echo "")
  OBS_MCP_HIT=$(echo "$OBS_MCP_RAW" | grep -i "obs" | head -1 || echo "")
  if [[ -z "$OBS_MCP_HIT" ]]; then
    OBS_MCP_STATUS="NOT REGISTERED (run install.sh)"
  else
    OBS_MCP_STATUS="OK: $OBS_MCP_HIT"
  fi
else
  OBS_MCP_STATUS="UNKNOWN (claude CLI not found)"
fi

# ---------------------------------------------------------------------------
# SECTION 5: Blocking issues + warnings + overall
# ---------------------------------------------------------------------------
BLOCKING=()
WARNINGS=()

# Look up index helpers (bash 3 compatible)
ffmpeg_status="MISSING"; ffprobe_status="MISSING"; node_status="MISSING"
for i in "${!TOOL_NAMES[@]}"; do
  case "${TOOL_NAMES[$i]}" in
    ffmpeg)  ffmpeg_status="${TOOL_STATUS[$i]}"  ;;
    ffprobe) ffprobe_status="${TOOL_STATUS[$i]}" ;;
    node)    node_status="${TOOL_STATUS[$i]}"    ;;
    yt-dlp)  ytdlp_status="${TOOL_STATUS[$i]}"  ;;
  esac
done
ytdlp_status="${ytdlp_status:-MISSING}"

crop_ok=0; loudnorm_ok=0; vidstab_detect_ok=0
for i in "${!FILT_NAMES[@]}"; do
  case "${FILT_NAMES[$i]}" in
    crop)          [[ "${FILT_STATUS[$i]}" == "OK" ]] && crop_ok=1 ;;
    loudnorm)      [[ "${FILT_STATUS[$i]}" == "OK" ]] && loudnorm_ok=1 ;;
    vidstabdetect) [[ "${FILT_STATUS[$i]}" == "OK" ]] && vidstab_detect_ok=1 ;;
  esac
done

[[ "$ffmpeg_status"  != "OK" ]] && BLOCKING+=("ffmpeg missing — core pipeline broken")
[[ "$ffprobe_status" != "OK" ]] && BLOCKING+=("ffprobe missing — probe.sh will fail")
[[ "$node_status"    != "OK" ]] && BLOCKING+=("node missing — obs-mcp / npx won't work")
[[ "$VENV_STATUS" == MISSING* ]] && BLOCKING+=("Python 3.11 venv not provisioned — bg-removal unavailable")
[[ "$VENV_STATUS" == "OK" && "$VENV_BGREMOVER" == "MISSING" ]] && \
  BLOCKING+=("backgroundremover not in venv — run install.sh")
[[ $crop_ok -eq 0     ]] && BLOCKING+=("ffmpeg filter 'crop' missing")
[[ $loudnorm_ok -eq 0 ]] && BLOCKING+=("ffmpeg filter 'loudnorm' missing")
[[ $vidstab_detect_ok -eq 0 ]] && WARNINGS+=("ffmpeg filter 'vidstabdetect' missing — stabilize disabled")

[[ "$VENV_STATUS" == "OK" && "$VENV_OTIO" == "MISSING" ]] && \
  WARNINGS+=("opentimelineio not in venv — OTIO->FCPXML export (Phase 5) unavailable")
[[ "$ytdlp_status" == "MISSING" ]] && WARNINGS+=("yt-dlp missing — URL ingest won't work")
echo "$OBS_MCP_STATUS" | grep -qi "not registered" && \
  WARNINGS+=("obs-mcp not registered — live capture (Phase 4) unavailable")

OVERALL="READY"
[[ ${#BLOCKING[@]} -gt 0 ]] && OVERALL="NOT READY"

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
if [[ "$JSON_MODE" -eq 1 ]]; then
  python3 - <<PYEOF
import json, sys

tools = {}
tool_names = "${TOOL_NAMES[*]}".split()
tool_status = "${TOOL_STATUS[*]}".split()
tool_vers = []
$(for i in "${!TOOL_NAMES[@]}"; do echo "tool_vers.append(\"${TOOL_VERS[$i]//\"/\\\"}\")"; done)

for i, name in enumerate(tool_names):
    s = tool_status[i] if i < len(tool_status) else "UNKNOWN"
    v = tool_vers[i]   if i < len(tool_vers)   else ""
    tools[name] = {"status": s, "version": v.split("\\n")[0][:80]}

tools["obs"] = {"status": "$OBS_STATUS", "version": "$OBS_VERS"}

filters = {}
filt_names = "${FILT_NAMES[*]}".split()
filt_status = "${FILT_STATUS[*]}".split()
for i, name in enumerate(filt_names):
    s = filt_status[i] if i < len(filt_status) else "UNKNOWN"
    filters[name] = s
filters["vidstab_twopass"]  = "$VIDSTAB2PASS"
filters["loudnorm_twopass"] = "$LOUDNORM2PASS"

blocking = [x for x in """${BLOCKING[*]:-}""".strip().split("\n") if x] if """${BLOCKING[*]:-}""".strip() else []
warnings = [x for x in """${WARNINGS[*]:-}""".strip().split("\n") if x] if """${WARNINGS[*]:-}""".strip() else []

out = {
    "overall":       "$OVERALL",
    "venv_dir":      "$VENV_DIR",
    "venv_status":   "$VENV_STATUS",
    "venv_python":   "$VENV_PYTHON_VER",
    "ml_tools": {
        "backgroundremover": "$VENV_BGREMOVER",
        "opentimelineio":    "$VENV_OTIO",
    },
    "tools":    tools,
    "filters":  filters,
    "obs_mcp":  "$OBS_MCP_STATUS",
    "blocking": blocking,
    "warnings": warnings,
}
print(json.dumps(out, indent=2))
PYEOF
  exit 0
fi

# ---------------------------------------------------------------------------
# Human-readable table (color codes; degrade gracefully if not a tty)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

row_ok()   { echo -e "  ${GREEN}[OK]${RESET}    $*"; }
row_warn() { echo -e "  ${YELLOW}[WARN]${RESET}  $*"; }
row_miss() { echo -e "  ${RED}[MISS]${RESET}  $*"; }

row_status() {
  local status="$1"; shift
  case "$status" in
    OK*) row_ok   "$@" ;;
    MI*) row_miss "$@" ;;
    *)   row_warn "$@" ;;
  esac
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         video-director — environment doctor           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Core CLI tools ──
echo -e "${BOLD}── Core CLI tools ──────────────────────────────────────${RESET}"
for i in "${!TOOL_NAMES[@]}"; do
  t="${TOOL_NAMES[$i]}"
  s="${TOOL_STATUS[$i]}"
  v=$(echo "${TOOL_VERS[$i]}" | head -1 | cut -c1-60)
  row_status "$s" "$t  ${v:+(${v})}"
done
row_status "$OBS_STATUS" "obs  ${OBS_VERS:+(${OBS_VERS})}"
echo ""

# ── Python 3.11 venv ──
echo -e "${BOLD}── Python 3.11 venv  ($VENV_DIR) ──${RESET}"
row_status "$VENV_STATUS"    "venv  ${VENV_PYTHON_VER}"
row_status "$VENV_BGREMOVER" "backgroundremover  (native video bg-removal)"
row_status "$VENV_OTIO"      "opentimelineio     (OTIO->FCPXML export, Phase 5)"
echo ""

# ── ffmpeg filters ──
echo -e "${BOLD}── ffmpeg filters ──────────────────────────────────────${RESET}"
for i in "${!FILT_NAMES[@]}"; do
  row_status "${FILT_STATUS[$i]}" "${FILT_NAMES[$i]}  — ${FILT_LABELS[$i]}"
done
echo ""

# ── Composite checks ──
echo -e "${BOLD}── Composite capability checks ─────────────────────────${RESET}"
row_status "$VIDSTAB2PASS"   "vidstab 2-pass  (both vidstabdetect + vidstabtransform)"
row_status "$LOUDNORM2PASS"  "loudnorm 2-pass (filter present; render.py handles passes)"
echo ""

# ── OBS-MCP ──
echo -e "${BOLD}── OBS-MCP registration ────────────────────────────────${RESET}"
case "$OBS_MCP_STATUS" in
  OK*) row_ok   "obs-mcp  — $OBS_MCP_STATUS" ;;
  *)   row_warn "obs-mcp  — $OBS_MCP_STATUS" ;;
esac
echo ""

# ── Summary ──
echo -e "${BOLD}── Summary ─────────────────────────────────────────────${RESET}"
if [[ "$OVERALL" == "READY" ]]; then
  echo -e "  ${GREEN}${BOLD}OVERALL: READY${RESET}"
else
  echo -e "  ${RED}${BOLD}OVERALL: NOT READY — fix blocking issues below${RESET}"
fi
echo ""

if [[ ${#BLOCKING[@]} -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}Blocking issues:${RESET}"
  for issue in "${BLOCKING[@]}"; do
    echo -e "  ${RED}  •${RESET} $issue"
  done
  echo ""
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}Warnings (non-blocking):${RESET}"
  for w in "${WARNINGS[@]}"; do
    echo -e "  ${YELLOW}  •${RESET} $w"
  done
  echo ""
fi

echo -e "  Skill dir: ${SKILL_DIR}"
echo -e "  Venv dir:  ${VENV_DIR}"
echo -e "  Run ${BOLD}install.sh${RESET} to provision missing items."
echo ""

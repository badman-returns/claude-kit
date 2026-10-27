#!/usr/bin/env bash
# handoff.sh — edl.json → OpenTimelineIO → edit.fcpxml
#
# Converts video-use's edl.json cut into an FCPXML timeline that imports into
# DaVinci Resolve (and Final Cut Pro) as a real multi-track, draggable timeline.
#
# The conversion is: edl.json → OTIO (in-memory) → FCPXML (via OTIO's adapter).
# OpenTimelineIO (OTIO) handles all the heavy lifting. This script is the glue.
#
# USAGE:
#   handoff.sh [OPTIONS] <edl.json>
#
# OPTIONS:
#   --out <path>      Output FCPXML path. Default: <edl_dir>/edit.fcpxml
#   --fps <n>         Frame rate to use for OTIO RationalTime. Default: auto-detect
#                     from first source via ffprobe. Fallback: 24.
#   --venv <path>     Director venv path. Default: ~/.video-director-venv
#   --dry-run         Print Python script to stdout; do not execute.
#   -h, --help        Print this help and exit.
#
# REQUIREMENTS:
#   ~/.video-director-venv must have opentimelineio installed.
#   install.sh provisions both backgroundremover (STEP 3) and opentimelineio (STEP 4).
#   If the venv or OTIO is missing, run install.sh first (the preflight below tells you).
#   Manual install if needed:  ~/.video-director-venv/bin/pip install opentimelineio
#
# SCOPE (v1):
#   • One video track: each edl.json range → one OTIO Clip with ExternalReference
#     to the absolute source path (so DaVinci can relink automatically).
#   • Source times are in seconds (float) from edl.json; converted to OTIO
#     RationalTime at the detected/specified FPS.
#   • Overlays and subtitles tracks: NOT included in v1. DaVinci user adds these
#     manually from the edit/ directory after import.
#   ⚠ Overlay/subtitle tracks in FCPXML: deferred to v2.
#
# OUTPUT:
#   edit.fcpxml alongside final.mp4 (or at --out path).
#   Import in DaVinci: File → Import → Timeline → (select edit.fcpxml).
#
# See references/preview-and-handoff.md for context on how this fits the workflow.

set -euo pipefail

EDL_FILE=""
OUT_FCPXML=""
FPS_OVERRIDE=""
VENV="${HOME}/.video-director-venv"
DRY_RUN=0

# ---------- arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)    OUT_FCPXML="$2"; shift ;;
    --fps)    FPS_OVERRIDE="$2"; shift ;;
    --venv)   VENV="$2"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '3,55p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    -*) echo "handoff.sh: unknown option: $1" >&2; exit 1 ;;
    *)  EDL_FILE="$1" ;;
  esac
  shift
done

if [[ -z "$EDL_FILE" ]]; then
  echo "handoff.sh: error: no edl.json path specified." >&2; exit 1
fi
if [[ ! -f "$EDL_FILE" ]]; then
  echo "handoff.sh: error: edl.json not found: $EDL_FILE" >&2; exit 1
fi

EDL_ABS="$(cd "$(dirname "$EDL_FILE")" && pwd)/$(basename "$EDL_FILE")"
EDL_DIR="$(dirname "$EDL_ABS")"
[[ -z "$OUT_FCPXML" ]] && OUT_FCPXML="${EDL_DIR}/edit.fcpxml"

PYTHON="${VENV}/bin/python"

# ---------- pre-flight ----------
# In --dry-run we only print the converter + planned command, so we do NOT need
# the venv to exist. This lets the exporter be inspected on a machine where the
# director venv has not been provisioned yet (install.sh not yet run).
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ ! -x "$PYTHON" ]]; then
    echo "handoff.sh: error: Python not found at ${PYTHON}" >&2
    echo "  Run install.sh to provision ~/.video-director-venv." >&2
    exit 1
  fi

  if ! "${PYTHON}" -c "import opentimelineio" &>/dev/null; then
    echo "handoff.sh: error: opentimelineio not installed in venv." >&2
    echo "  Install it via install.sh STEP 4, or directly:" >&2
    echo "    ${VENV}/bin/pip install opentimelineio" >&2
    exit 1
  fi
fi

# ---------- auto-detect FPS from first source ----------
# FPS detection only needs stdlib (json, eval) — not OTIO — so pick whatever
# python is available (the venv may not exist yet during --dry-run). This keeps
# FPS detection decoupled from venv provisioning.
PYHELP="$PYTHON"
[[ -x "$PYHELP" ]] || PYHELP="$(command -v python3 || command -v python3.11 || true)"

if [[ -z "$FPS_OVERRIDE" && -n "$PYHELP" ]]; then
  # Extract first source path from edl.json using python -c (avoids jq dependency)
  FIRST_SOURCE="$("${PYHELP}" -c "
import json, sys
data = json.load(open('${EDL_ABS}'))
sources = data.get('sources', {})
if sources:
    print(list(sources.values())[0])
" 2>/dev/null || true)"

  if [[ -n "$FIRST_SOURCE" && -f "$FIRST_SOURCE" ]]; then
    # ffprobe r_frame_rate returns e.g. "24000/1001" or "30/1"
    # default=nw=1:nk=1 emits just the bare value; csv=p=0 can append a stray
    # trailing comma (e.g. "30/1,") that breaks the eval below. Strip to the
    # fraction characters only.
    RFRAME="$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$FIRST_SOURCE" 2>/dev/null | \
      head -1 | tr -cd '0-9/')"
    if [[ -n "$RFRAME" ]]; then
      # Evaluate fraction to float using python
      FPS="$("${PYHELP}" -c "print(round(eval('${RFRAME}'), 3))" 2>/dev/null || echo "")"
      if [[ -n "$FPS" && "$FPS" != "0" ]]; then
        echo "handoff.sh: detected FPS=${FPS} from ${FIRST_SOURCE}"
      else
        FPS="24"
        echo "handoff.sh: WARNING: could not parse FPS '${RFRAME}'; using fallback 24."
      fi
    else
      FPS="24"
      echo "handoff.sh: WARNING: ffprobe returned no frame rate; using fallback FPS=24."
    fi
  else
    FPS="24"
    echo "handoff.sh: WARNING: first source not accessible for FPS detection; using fallback FPS=24."
  fi
elif [[ -n "$FPS_OVERRIDE" ]]; then
  FPS="$FPS_OVERRIDE"
  echo "handoff.sh: using FPS=${FPS} (from --fps)."
else
  FPS="24"
  echo "handoff.sh: WARNING: no python available for FPS detection; using fallback FPS=24."
fi

# ---------- inline Python converter ----------
PYTHON_SCRIPT="$(cat <<'PYEOF'
"""
edl.json → OpenTimelineIO → edit.fcpxml

v1 scope: one video track; each range becomes an OTIO Clip with
ExternalReference to the absolute source path. Source times in
seconds (floats) → RationalTime at the specified FPS.

Overlays and subtitle tracks are NOT included in v1 (deferred).
"""

import json
import sys
import opentimelineio as otio

edl_path = sys.argv[1]
out_path  = sys.argv[2]
fps       = float(sys.argv[3])

with open(edl_path) as f:
    edl = json.load(f)

sources  = edl.get("sources", {})
ranges   = edl.get("ranges",  [])

if not ranges:
    print("handoff.sh [python]: WARNING: edl.json has no ranges; empty timeline.", file=sys.stderr)

# OTIO rate — use a Fraction-based rate where possible for common film/video rates.
# For 23.976 (24000/1001) OTIO wants 24 * 1000/1001 or you can pass the float; FCPXML
# adapter normalises. We use the float fps for simplicity in v1.
rate = fps

timeline = otio.schema.Timeline(name="video-director edit")
track    = otio.schema.Track(name="V1", kind=otio.schema.TrackKind.Video)

for rng in ranges:
    src_name  = rng["source"]
    src_path  = sources.get(src_name)
    if src_path is None:
        print(f"handoff.sh [python]: WARNING: source '{src_name}' not found in sources dict — skipping.", file=sys.stderr)
        continue

    t_start = float(rng["start"])
    t_end   = float(rng["end"])

    if t_end <= t_start:
        print(f"handoff.sh [python]: WARNING: range [{t_start}, {t_end}] for {src_name} has zero/negative duration — skipping.", file=sys.stderr)
        continue

    media_ref = otio.schema.ExternalReference(
        target_url=src_path,
        available_range=otio.opentime.TimeRange(
            start_time    = otio.opentime.RationalTime(0, rate),
            duration      = otio.opentime.RationalTime(1e9, rate),  # unbounded; DaVinci relinks
        )
    )

    clip = otio.schema.Clip(
        name           = f"{src_name} [{t_start:.2f}-{t_end:.2f}]",
        media_reference= media_ref,
        source_range   = otio.opentime.TimeRange(
            start_time = otio.opentime.RationalTime(t_start * rate, rate),
            duration   = otio.opentime.RationalTime((t_end - t_start) * rate, rate),
        )
    )
    track.append(clip)

timeline.tracks.append(track)

# ⚠ Overlays and subtitle tracks not included in v1.
# To add: create additional otio.schema.Track entries for each overlay/subtitle.

otio.adapters.write_to_file(timeline, out_path)
print(f"handoff.sh [python]: written {len(track)} clips → {out_path}")
PYEOF
)"

# ---------- run (or dry-run) ----------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] Would execute Python converter:"
  echo "  ${PYTHON} -c '<script>' '${EDL_ABS}' '${OUT_FCPXML}' '${FPS}'"
  echo ""
  echo "--- Python script ---"
  echo "${PYTHON_SCRIPT}"
  echo "--- end ---"
  exit 0
fi

echo "handoff.sh: converting edl.json → ${OUT_FCPXML} at ${FPS} fps..."

"${PYTHON}" - "$EDL_ABS" "$OUT_FCPXML" "$FPS" <<< "${PYTHON_SCRIPT}"

echo ""
echo "handoff.sh: DONE → ${OUT_FCPXML}"
echo "handoff.sh: Import in DaVinci: File → Import → Timeline → (select edit.fcpxml)"
echo ""
echo "⚠ OPEN: Verify import in DaVinci Resolve — OTIO→FCPXML adapter output"
echo "  has not been tested end-to-end in this environment."
echo "⚠ OPEN: Overlays and subtitle tracks are NOT exported (v1 scope)."
echo "  Add them manually from the edit/ directory after import."

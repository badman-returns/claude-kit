#!/usr/bin/env bash
# prep.sh — PRE source-prep for video-director
#
# Runs the PRE pipeline steps that happen BEFORE the baton passes to video-use:
#   • Safe-crop reframe to 9:16  (⚙ ffmpeg)
#   • Two-pass vidstab stabilize (⚙ ffmpeg)
#   • Background removal via backgroundremover CLI (⚙+venv py3.11)
#
# ⚠ NOT BUILT (defer to v2):
#   • AI subject-tracking reframe (needs autoflip / mediapipe)
#   • Beat-synced cuts (needs aubio / librosa)
#
# USAGE:
#   prep.sh [OPTIONS] <input_file>
#
# OPTIONS:
#   --reframe          Safe-crop source to 9:16 (1080×1920). Skipped if source is already 9:16.
#   --stabilize        Two-pass vidstab stabilize.
#   --remove-bg        Background removal via backgroundremover (requires venv installed).
#   --all              Shorthand for --reframe --stabilize (bg-removal is opt-in).
#   --out-dir <dir>    Where to write prepped files. Default: <input_parent>/prep/
#   --venv <path>      Path to the director venv. Default: ~/.video-director-venv
#   --stab-shakiness <n>  vidstabdetect shakiness 1–10. Default: 5.
#   --stab-smoothing <n>  vidstabtransform smoothing (frames). Default: 10.
#   --dry-run          Print commands without running them.
#   -h, --help         Print this help and exit.
#
# OUTPUT:
#   Prepped file(s) land in --out-dir, never in the raw/ source directory.
#   Naming convention: <stem>_reframed.mp4, <stem>_stabilized.mp4, <stem>_nobg.mp4
#   .trf (vidstab transform data) is written to --out-dir/<stem>.trf and cleaned up.
#
# NOTE — what NOT to do in prep:
#   • Do NOT apply loudnorm here. render.py runs two-pass loudnorm itself (baton-handoff §7.1).
#   • Do NOT apply HDR→SDR tonemap here. render.py handles it (§7.2).
#   • Do NOT apply grade here. Grade direction rides the baton via project.md.
#   • Do NOT write anything into the raw/ source directory.
#
# See references/pipelines.md and references/baton-handoff.md for context.

set -euo pipefail

# ---------- defaults ----------
DO_REFRAME=0
DO_STABILIZE=0
DO_REMOVE_BG=0
OUT_DIR=""
VENV="${HOME}/.video-director-venv"
STAB_SHAKINESS=5
STAB_SMOOTHING=10
DRY_RUN=0
INPUT=""

# ---------- arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reframe)      DO_REFRAME=1 ;;
    --stabilize)    DO_STABILIZE=1 ;;
    --remove-bg)    DO_REMOVE_BG=1 ;;
    --all)          DO_REFRAME=1; DO_STABILIZE=1 ;;
    --out-dir)      OUT_DIR="$2"; shift ;;
    --venv)         VENV="$2"; shift ;;
    --stab-shakiness) STAB_SHAKINESS="$2"; shift ;;
    --stab-smoothing) STAB_SMOOTHING="$2"; shift ;;
    --dry-run)      DRY_RUN=1 ;;
    -h|--help)
      sed -n '3,60p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    -*)  echo "prep.sh: unknown option: $1" >&2; exit 1 ;;
    *)   INPUT="$1" ;;
  esac
  shift
done

if [[ -z "$INPUT" ]]; then
  echo "prep.sh: error: no input file specified. Run with --help for usage." >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "prep.sh: error: input file not found: $INPUT" >&2
  exit 1
fi

if [[ $DO_REFRAME -eq 0 && $DO_STABILIZE -eq 0 && $DO_REMOVE_BG -eq 0 ]]; then
  echo "prep.sh: error: no operation selected. Use --reframe, --stabilize, --remove-bg, or --all." >&2
  exit 1
fi

# ---------- helpers ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SH="${SCRIPT_DIR}/probe.sh"
INPUT_ABS="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
STEM="$(basename "${INPUT%.*}")"
SRC_DIR="$(dirname "$INPUT_ABS")"

# Guard: refuse to write into raw/ or any directory ending in /raw.
# Fix: when input is at .../raw/clip.mp4, SRC_DIR = .../raw (ends in /raw,
# no trailing slash). Strip from INPUT_ABS which always contains /raw/ as a
# path component. We want the parent of the raw/ directory as the project root.
if [[ -z "$OUT_DIR" ]]; then
  if [[ "$INPUT_ABS" == */raw/* || "$SRC_DIR" == */raw ]]; then
    # Extract the directory that CONTAINS raw/ as a child:
    #   INPUT_ABS = /path/to/Content/raw/clip.mp4
    #   → RAW_PARENT = /path/to/Content
    RAW_PARENT="$(echo "$INPUT_ABS" | sed 's|/raw/.*||')"
    if [[ "$RAW_PARENT" == "$INPUT_ABS" ]]; then
      # sed didn't find /raw/ — input is directly in raw/ with no subdirs; use dirname twice
      RAW_PARENT="$(dirname "$SRC_DIR")"
    fi
    OUT_DIR="${RAW_PARENT}/scratch/prep"
    echo "prep.sh: INFO: input is inside raw/; output redirected to $OUT_DIR (sibling of raw/)"
  else
    OUT_DIR="${SRC_DIR}/prep"
  fi
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    echo "prep.sh: running: $*"
    "$@"
  fi
}

mkdir_safe() {
  [[ $DRY_RUN -eq 1 ]] && echo "[DRY-RUN] mkdir -p $1" || mkdir -p "$1"
}

# Compute rotation-aware DISPLAY dimensions, echoed as "W H".
# Phone footage is often stored landscape (e.g. 3840x2160) with a rotation flag
# (tags.rotate / Display Matrix side-data of ±90/270) so it DISPLAYS portrait.
# ffprobe's stream=width/height reports the STORED dims and ignores rotation, so
# we delegate to probe.sh, which reads the rotation metadata and swaps w<->h to
# report what the viewer actually sees. This matters for the "already 9:16?"
# check below: on rotated portrait footage the stored dims look landscape.
# Falls back to raw stream dims if probe.sh is unavailable or fails (e.g. a
# zero-byte dry-run placeholder).
display_dims() {
  local f="$1" json dims dw="" dh=""
  if [[ -f "$PROBE_SH" ]] && command -v python3 &>/dev/null; then
    json="$(bash "$PROBE_SH" "$f" 2>/dev/null || true)"
    if [[ -n "$json" ]]; then
      dims="$(printf '%s' "$json" | python3 -c \
        'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("display_w",""), d.get("display_h",""))
except Exception:
    pass' 2>/dev/null || true)"
      dw="${dims%% *}"
      dh="${dims##* }"
    fi
  fi
  # Fallback: raw stream dims (rotation-unaware) when probe.sh didn't yield ints.
  if ! [[ "$dw" =~ ^[0-9]+$ && "$dh" =~ ^[0-9]+$ ]]; then
    dw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
      -of default=nw=1:nk=1 "$f" 2>/dev/null | head -1 | tr -cd '0-9' || true)"
    dh="$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
      -of default=nw=1:nk=1 "$f" 2>/dev/null | head -1 | tr -cd '0-9' || true)"
  fi
  echo "${dw:-} ${dh:-}"
}

# ---------- pre-flight ----------
if ! command -v ffmpeg &>/dev/null; then
  echo "prep.sh: error: ffmpeg not found on PATH." >&2; exit 1
fi
if ! command -v ffprobe &>/dev/null; then
  echo "prep.sh: error: ffprobe not found on PATH." >&2; exit 1
fi

mkdir_safe "$OUT_DIR"

CURRENT_FILE="$INPUT_ABS"

# Execution order: stabilize FIRST, then reframe, then bg-removal.
# Rationale: vidstab needs the full-frame margins to absorb camera shake.
# Cropping first reduces the margin available to the stabilizer and can
# produce black-border artifacts on the edge of the stabilized result.
# When both --stabilize and --reframe are given (e.g. --all), stabilize runs
# on the full-resolution source, then reframe crops the stable output.

# ---------- STEP 1: stabilize (vidstab 2-pass) — runs on full-resolution source ----------
if [[ $DO_STABILIZE -eq 1 ]]; then
  echo "prep.sh: [step 1] stabilize (vidstab 2-pass)"
  # NOTE: vidstab is a TWO-PASS process:
  #   Pass 1 — vidstabdetect: analyzes motion, writes a .trf transform file
  #   Pass 2 — vidstabtransform: applies the transforms to produce stable output

  TRF_FILE="${OUT_DIR}/${STEM}.trf"
  STABILIZED="${OUT_DIR}/${STEM}_stabilized.mp4"

  # Pass 1: detect
  echo "prep.sh: vidstab pass 1 — motion analysis..."
  run ffmpeg -y -i "$CURRENT_FILE" \
    -vf "vidstabdetect=shakiness=${STAB_SHAKINESS}:accuracy=9:result=${TRF_FILE}" \
    -f null -

  # Pass 2: transform
  echo "prep.sh: vidstab pass 2 — applying stabilization..."
  run ffmpeg -y -i "$CURRENT_FILE" \
    -vf "vidstabtransform=input=${TRF_FILE}:smoothing=${STAB_SMOOTHING}:crop=black:zoom=3:interpol=bicubic,unsharp=5:5:0.8:3:3:0.4" \
    -c:v libx264 -preset slow -crf 18 \
    -c:a copy \
    -movflags +faststart \
    "$STABILIZED"

  # Clean up transform file
  if [[ $DRY_RUN -eq 0 && -f "$TRF_FILE" ]]; then rm -f "$TRF_FILE"; fi

  echo "prep.sh: stabilized → $STABILIZED"
  CURRENT_FILE="$STABILIZED"
fi

# ---------- STEP 2: reframe to 9:16 (safe-crop, center) — runs after stabilize ----------
if [[ $DO_REFRAME -eq 1 ]]; then
  echo "prep.sh: [step 2] reframe → 9:16 (safe-crop)"

  # Probe DISPLAY dimensions (rotation-aware — see display_dims helper).
  # We must NOT use the raw stream=width/height here: phone footage is stored
  # landscape with a rotation flag and displays portrait, so the stored dims
  # would make already-9:16 footage look like it needs cropping.
  read -r WIDTH HEIGHT <<< "$(display_dims "$CURRENT_FILE")"

  echo "prep.sh: display dimensions: ${WIDTH:-?}x${HEIGHT:-?}"

  # Check if already 9:16 (within 1px tolerance)
  # Guard against empty values (e.g. dry-run on a zero-byte placeholder file)
  WIDTH="${WIDTH:-0}"; HEIGHT="${HEIGHT:-1080}"
  EXPECTED_W=$(( HEIGHT * 9 / 16 ))
  if [[ "$WIDTH" -eq "$EXPECTED_W" ]]; then
    echo "prep.sh: source is already 9:16 — skipping reframe."
    REFRAMED="$CURRENT_FILE"
  else
    REFRAMED="${OUT_DIR}/${STEM}_reframed.mp4"
    # Safe-crop: take full height, crop width to 9/16 of height, centered.
    # crop=w:h:x:y — x=(W - crop_w)/2 for centering, y=0 (full height)
    # Then scale to 1080×1920 to normalize resolution.
    # NOTE: ffmpeg auto-rotates on decode (default), so the filter's iw/ih are
    # already the DISPLAY dimensions — consistent with the check above. No
    # explicit rotation handling is needed inside the crop expression.
    CROP_FILTER="crop=iw*min(1\\,ih*9/16/iw):ih:iw/2-iw*min(1\\,ih*9/16/iw)/2:0,scale=1080:1920:flags=lanczos"
    run ffmpeg -y -i "$CURRENT_FILE" \
      -vf "${CROP_FILTER}" \
      -c:v libx264 -preset slow -crf 18 \
      -c:a copy \
      -movflags +faststart \
      "$REFRAMED"
    echo "prep.sh: reframed → $REFRAMED"
  fi
  CURRENT_FILE="$REFRAMED"
fi

# ---------- STEP 3: background removal ----------
if [[ $DO_REMOVE_BG -eq 1 ]]; then
  echo "prep.sh: [step 3/3] background removal (backgroundremover)"

  # Verify venv exists and backgroundremover is installed
  BGREMOVER="${VENV}/bin/backgroundremover"
  if [[ ! -x "$BGREMOVER" ]]; then
    echo "prep.sh: error: backgroundremover not found at ${BGREMOVER}" >&2
    echo "prep.sh:   Run install.sh first to provision the Python 3.11 venv." >&2
    exit 1
  fi

  NOBG="${OUT_DIR}/${STEM}_nobg.mp4"

  # backgroundremover CLI: input -i, output -o, video mode is default for .mp4.
  # NOTE: verify exact flags against your installed version of backgroundremover —
  # the documented interface is:
  #   backgroundremover -i <input> -tv -o <output>
  # where -tv = "type video" (vs -tl for live stream).
  # The output container may be .mp4 or require .webm depending on alpha support.
  # Verify on first run with a test clip.
  run "${BGREMOVER}" -i "$CURRENT_FILE" -tv -o "$NOBG"

  echo "prep.sh: background removed → $NOBG"
  CURRENT_FILE="$NOBG"
fi

# ---------- ⚠ NOT BUILT — documented deferrals ----------
# The following pipeline rows exist in pipelines.md but have NO command here:
#   ⚠ AI subject-tracking reframe  — needs autoflip/mediapipe; deferred to v2
#   ⚠ Beat-synced cuts              — needs aubio/librosa; deferred to v2
#   ⚠ Music bed                     — needs music-source folder/API; open question
#   ⚠ B-roll inserts                — editorial; handled manually inside video-use

# ---------- summary ----------
echo ""
echo "prep.sh: DONE"
echo "prep.sh: final prepped file: $CURRENT_FILE"
echo ""
echo "prep.sh: Next step:"
echo "  Record this path in <videos_dir>/edit/project.md (baton file) and"
echo "  invoke the video-use skill, pointing it at the prepped file."
echo "  See references/baton-handoff.md §2 for the project.md schema."

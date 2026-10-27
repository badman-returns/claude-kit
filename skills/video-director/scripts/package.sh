#!/usr/bin/env bash
# package.sh — POST platform-correct encode for video-director
#
# Reads final.mp4 (output of video-use's render.py) and produces a
# platform-correct delivery file with the right aspect ratio, codec,
# bitrate, and container. Does NOT re-grade, re-tonemap, or re-normalize
# loudness by default — render.py already handles those (baton-handoff §7).
#
# USAGE:
#   package.sh [OPTIONS] --platform <key> <input_file>
#
# PLATFORMS (see references/platform-presets.md for full spec):
#   ig_reel        Instagram Reel  9:16 1080×1920 H.264 8Mbps
#   yt_shorts      YouTube Shorts  9:16 1080×1920 H.264 8Mbps
#   tiktok         TikTok          9:16 1080×1920 H.264 8Mbps
#   yt_long        YouTube (long)  16:9 1920×1080 H.264 12Mbps
#   yt_4k          YouTube 4K      16:9 3840×2160 H.265 45Mbps
#   ig_feed_45     IG Feed 4:5     4:5  1080×1350 H.264 8Mbps
#   ig_feed_11     IG Feed 1:1     1:1  1080×1080 H.264 8Mbps
#   x_16_9         X/Twitter 16:9  16:9 1920×1080 H.264 8Mbps
#   x_1_1          X/Twitter 1:1   1:1  1200×1200 H.264 8Mbps
#
# OPTIONS:
#   --platform <key>       Required. Platform key from list above.
#   --out-dir <dir>        Output directory. Default: <input_parent>/deliver/
#   --reframe-crop         Crop to fit platform aspect (default: pad/letterbox).
#   --pad-color <hex>      Padding color. Default: 000000 (black).
#   --force-loudnorm       Force two-pass loudnorm re-normalization. Use only when
#                          input is NOT from video-use (render.py already normalizes).
#   --no-audio-verify      Skip loudness measurement. Faster but no LUFS report.
#   --dry-run              Print commands without running them.
#   --emit-fcpxml          After encoding, call handoff.sh to produce edit.fcpxml.
#   -h, --help             Print this help and exit.
#
# OUTPUT:
#   <out_dir>/<stem>_<platform>.mp4
#   (loudness report printed to stdout; no separate file unless --emit-fcpxml)
#
# SAFETY NOTES:
#   • Never writes into the source directory or edit/ directory.
#   • Never re-grades or re-tonemaps (render.py already did that).
#   • Loudness: measures only by default (render.py ran loudnorm; re-running
#     double-processes audio). Use --force-loudnorm ONLY for non-video-use inputs.
#
# See references/platform-presets.md and references/baton-handoff.md §7.

set -euo pipefail

PLATFORM=""
OUT_DIR=""
REFRAME_CROP=0
PAD_COLOR="000000"
FORCE_LOUDNORM=0
NO_AUDIO_VERIFY=0
DRY_RUN=0
EMIT_FCPXML=0
INPUT=""
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------- arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)      PLATFORM="$2"; shift ;;
    --out-dir)       OUT_DIR="$2"; shift ;;
    --reframe-crop)  REFRAME_CROP=1 ;;
    --pad-color)     PAD_COLOR="$2"; shift ;;
    --force-loudnorm) FORCE_LOUDNORM=1 ;;
    --no-audio-verify) NO_AUDIO_VERIFY=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --emit-fcpxml)   EMIT_FCPXML=1 ;;
    -h|--help)
      sed -n '3,65p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    -*) echo "package.sh: unknown option: $1" >&2; exit 1 ;;
    *)  INPUT="$1" ;;
  esac
  shift
done

if [[ -z "$INPUT" ]]; then
  echo "package.sh: error: no input file specified." >&2; exit 1
fi
if [[ ! -f "$INPUT" ]]; then
  echo "package.sh: error: input file not found: $INPUT" >&2; exit 1
fi
if [[ -z "$PLATFORM" ]]; then
  echo "package.sh: error: --platform is required." >&2; exit 1
fi

INPUT_ABS="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
STEM="$(basename "${INPUT%.*}")"
SRC_DIR="$(dirname "$INPUT_ABS")"

# ---------- preset lookup ----------
# Values match references/platform-presets.md exactly. Update both together.
case "$PLATFORM" in
  ig_reel|yt_shorts|tiktok)
    TARGET_W=1080; TARGET_H=1920
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=8M; MAXRATE=9600k; BUFSIZE=16M
    ACODEC=aac; ABITRATE=192k ;;
  yt_long)
    TARGET_W=1920; TARGET_H=1080
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=12M; MAXRATE=14400k; BUFSIZE=24M
    ACODEC=aac; ABITRATE=192k ;;
  yt_4k)
    TARGET_W=3840; TARGET_H=2160
    VCODEC=libx265; PROFILE=main; LEVEL=5.1
    VBITRATE=45M; MAXRATE=54M; BUFSIZE=90M
    ACODEC=aac; ABITRATE=192k ;;
  ig_feed_45)
    TARGET_W=1080; TARGET_H=1350
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=8M; MAXRATE=9600k; BUFSIZE=16M
    ACODEC=aac; ABITRATE=192k ;;
  ig_feed_11)
    TARGET_W=1080; TARGET_H=1080
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=8M; MAXRATE=9600k; BUFSIZE=16M
    ACODEC=aac; ABITRATE=192k ;;
  x_16_9)
    TARGET_W=1920; TARGET_H=1080
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=8M; MAXRATE=9600k; BUFSIZE=16M
    ACODEC=aac; ABITRATE=192k ;;
  x_1_1)
    TARGET_W=1200; TARGET_H=1200
    VCODEC=libx264; PROFILE=high; LEVEL=4.0
    VBITRATE=8M; MAXRATE=9600k; BUFSIZE=16M
    ACODEC=aac; ABITRATE=192k ;;
  *)
    echo "package.sh: error: unknown platform '$PLATFORM'." >&2
    echo "  Valid keys: ig_reel yt_shorts tiktok yt_long yt_4k ig_feed_45 ig_feed_11 x_16_9 x_1_1" >&2
    exit 1 ;;
esac

# ---------- output location ----------
# Default: if input is inside an edit/ directory (the normal case — render.py
# writes to <videos_dir>/edit/final.mp4), place deliver/ as a SIBLING of edit/,
# not inside it. If input is elsewhere, place deliver/ next to the input.
if [[ -z "$OUT_DIR" ]]; then
  if [[ "$(basename "$SRC_DIR")" == "edit" ]]; then
    OUT_DIR="$(dirname "$SRC_DIR")/deliver"
  else
    OUT_DIR="${SRC_DIR}/deliver"
  fi
fi

# Guard: never write into the source's edit/ or raw/ directory trees.
# Compare the resolved absolute path prefix rather than a substring to avoid
# false trips on dirs like /credit/ or /editors/.
EDIT_GUARD="$(cd "$(dirname "$INPUT_ABS")" && pwd)"
if [[ "$OUT_DIR" == "$EDIT_GUARD"* && "$OUT_DIR" != "$EDIT_GUARD/deliver"* ]] || \
   [[ "$OUT_DIR" == */raw/* || "$OUT_DIR" == */raw ]]; then
  echo "package.sh: error: OUT_DIR '${OUT_DIR}' must not be inside the source edit/ or raw/ tree." >&2
  echo "  Use --out-dir to specify an explicit output directory." >&2
  exit 1
fi

OUTPUT="${OUT_DIR}/${STEM}_${PLATFORM}.mp4"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    echo "package.sh: running: $*"
    "$@"
  fi
}

mkdir_safe() {
  [[ $DRY_RUN -eq 1 ]] && echo "[DRY-RUN] mkdir -p $1" || mkdir -p "$1"
}

mkdir_safe "$OUT_DIR"

# ---------- HDR detection ----------
COLORSPACE="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=color_transfer -of csv=p=0 "$INPUT_ABS" 2>/dev/null | tr -d ' ' || true)"

HDR_TONEMAP_FILTER=""
if [[ "$COLORSPACE" == "smpte2084" || "$COLORSPACE" == "arib-std-b67" ]]; then
  echo "package.sh: WARNING: HDR input detected (${COLORSPACE})."
  echo "  render.py should have tonemapped this already (baton-handoff §7.2)."
  echo "  Applying zscale+tonemap as fallback — verify output carefully."
  HDR_TONEMAP_FILTER="zscale=t=linear:npl=100,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,"
fi

# ---------- probe source dimensions ----------
SRC_W="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width -of csv=p=0 "$INPUT_ABS" 2>/dev/null | tr -d ' ' || true)"
SRC_H="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=height -of csv=p=0 "$INPUT_ABS" 2>/dev/null | tr -d ' ' || true)"

echo "package.sh: source ${SRC_W}x${SRC_H} → target ${TARGET_W}x${TARGET_H} [${PLATFORM}]"

# ---------- aspect / scale / pad filter ----------
# Decide: scale to fit, then pad (default) or crop to fill (--reframe-crop).
# "Scale to fit" = letterbox/pillarbox: scale inside target box, pad remainder.
# "Crop to fill" = scale to cover target, then crop center.
if [[ $REFRAME_CROP -eq 1 ]]; then
  # Scale to cover, then center-crop
  SCALE_FILTER="scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=increase,crop=${TARGET_W}:${TARGET_H}"
else
  # Scale to fit, pad (letterbox/pillarbox)
  SCALE_FILTER="scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=decrease,pad=${TARGET_W}:${TARGET_H}:(ow-iw)/2:(oh-ih)/2:${PAD_COLOR}"
fi

VIDEO_FILTER="${HDR_TONEMAP_FILTER}${SCALE_FILTER}"

# ---------- loudness: measure first (default path) ----------
if [[ $NO_AUDIO_VERIFY -eq 0 && $DRY_RUN -eq 0 ]]; then
  echo "package.sh: measuring loudness of input (render.py should have normalized this)..."
  LUFS_REPORT="$(ffmpeg -nostats -i "$INPUT_ABS" \
    -af "ebur128=framelog=verbose" -f null - 2>&1 | \
    grep -E 'I:|LRA:|True peak' | tail -3 || true)"
  if [[ -n "$LUFS_REPORT" ]]; then
    echo "package.sh: loudness report:"
    echo "$LUFS_REPORT" | sed 's/^/  /'
    # Extract integrated LUFS to warn if out of range
    INT_LUFS="$(echo "$LUFS_REPORT" | grep -oE 'I:[[:space:]]*[-0-9.]+' | grep -oE '[-0-9.]+' | head -1 || true)"
    if [[ -n "$INT_LUFS" ]]; then
      # Compare using awk (bash can't do float comparison natively)
      if awk "BEGIN{exit !($INT_LUFS < -16 || $INT_LUFS > -12)}"; then
        echo "package.sh: WARNING: integrated LUFS=${INT_LUFS} is outside [-16, -12] range."
        echo "  Expected ~-14 LUFS from render.py. If this is a non-video-use input,"
        echo "  re-run with --force-loudnorm."
      fi
    fi
  fi
fi

# ---------- loudnorm (only if --force-loudnorm) ----------
# WARNING: do NOT run this on render.py output — it is already normalized.
# This path is for non-video-use inputs (raw clips, externally edited files).
AUDIO_FILTER_ARGS=""
if [[ $FORCE_LOUDNORM -eq 1 ]]; then
  echo "package.sh: --force-loudnorm: running two-pass loudnorm (I=-14:TP=-1:LRA=11)..."
  if [[ $DRY_RUN -eq 0 ]]; then
    # Pass 1: measure
    LOUDNORM_PASS1="$(ffmpeg -i "$INPUT_ABS" \
      -af "loudnorm=I=-14:TP=-1:LRA=11:print_format=json" \
      -f null - 2>&1 | grep -A 12 '"input_i"' || true)"
    MEAS_I="$(echo "$LOUDNORM_PASS1" | grep '"input_i"' | grep -oE '"-?[0-9.]+"' | tr -d '"' | head -1)"
    MEAS_TP="$(echo "$LOUDNORM_PASS1" | grep '"input_tp"' | grep -oE '"-?[0-9.]+"' | tr -d '"' | head -1)"
    MEAS_LRA="$(echo "$LOUDNORM_PASS1" | grep '"input_lra"' | grep -oE '"-?[0-9.]+"' | tr -d '"' | head -1)"
    MEAS_THRESH="$(echo "$LOUDNORM_PASS1" | grep '"input_thresh"' | grep -oE '"-?[0-9.]+"' | tr -d '"' | head -1)"
    echo "package.sh: loudnorm pass1: I=${MEAS_I} TP=${MEAS_TP} LRA=${MEAS_LRA}"
    # Pass 2 filter (linear mode for accuracy)
    AUDIO_FILTER_ARGS="-af loudnorm=I=-14:TP=-1:LRA=11:measured_I=${MEAS_I}:measured_TP=${MEAS_TP}:measured_LRA=${MEAS_LRA}:measured_thresh=${MEAS_THRESH}:offset=0:linear=true:print_format=summary"
  else
    echo "[DRY-RUN] (loudnorm pass1 measurement skipped)"
    AUDIO_FILTER_ARGS="-af loudnorm=I=-14:TP=-1:LRA=11:linear=true"
  fi
fi

# ---------- encode ----------
echo "package.sh: encoding → $OUTPUT"

# Build ffmpeg args
FF_VIDEO_ARGS=(-vf "${VIDEO_FILTER}")
if [[ "$VCODEC" == "libx265" ]]; then
  FF_VIDEO_ARGS+=(-c:v libx265 -profile:v "${PROFILE}" -level "${LEVEL}"
    -b:v "${VBITRATE}" -maxrate "${MAXRATE}" -bufsize "${BUFSIZE}"
    -tag:v hvc1)
else
  FF_VIDEO_ARGS+=(-c:v libx264 -profile:v "${PROFILE}" -level "${LEVEL}"
    -b:v "${VBITRATE}" -maxrate "${MAXRATE}" -bufsize "${BUFSIZE}")
fi

FF_AUDIO_ARGS=(-c:a "${ACODEC}" -b:a "${ABITRATE}")
[[ -n "${AUDIO_FILTER_ARGS}" ]] && FF_AUDIO_ARGS=(${AUDIO_FILTER_ARGS} "${FF_AUDIO_ARGS[@]}")

run ffmpeg -y -i "$INPUT_ABS" \
  "${FF_VIDEO_ARGS[@]}" \
  "${FF_AUDIO_ARGS[@]}" \
  -movflags +faststart \
  "$OUTPUT"

# ---------- optional FCPXML handoff ----------
if [[ $EMIT_FCPXML -eq 1 ]]; then
  EDL_FILE="$(dirname "$INPUT_ABS")/edl.json"
  if [[ -f "$EDL_FILE" ]]; then
    echo "package.sh: --emit-fcpxml: calling handoff.sh..."
    HANDOFF_SH="${SKILL_DIR}/scripts/handoff.sh"
    if [[ -x "$HANDOFF_SH" ]]; then
      run "${HANDOFF_SH}" "$EDL_FILE" --out "$(dirname "$OUTPUT")/edit.fcpxml"
    else
      echo "package.sh: WARNING: handoff.sh not found or not executable at ${HANDOFF_SH}" >&2
    fi
  else
    echo "package.sh: WARNING: --emit-fcpxml set but edl.json not found at ${EDL_FILE}." >&2
  fi
fi

# ---------- done ----------
echo ""
echo "package.sh: DONE → $OUTPUT"
if [[ $DRY_RUN -eq 0 ]]; then
  echo "package.sh: file size: $(du -sh "$OUTPUT" | cut -f1)"
fi

#!/usr/bin/env bash
# probe.sh — ffprobe wrapper → normalized JSON
#
# Output fields: file_path, file_size_mb, container, duration_s, fps,
#   display_w, display_h, aspect, orientation,
#   source_w, source_h, rotation_deg, rotation_note,
#   video_codec, bit_rate_kbps, color_space, color_primaries, color_transfer,
#   hdr (bool), hdr_type, has_audio, audio_codec, sample_rate_hz, channels,
#   loudness_lufs, loudness_lra, loudness_tp_dbfs
#
# ROTATION GOTCHA (handled):
#   A phone clip shot portrait may be stored as a 3840x2160 (landscape) stream
#   with a rotation tag of -90 (or 90/270). ffprobe reports SOURCE dimensions.
#   This script detects the rotation and swaps w↔h to give DISPLAY dimensions
#   that match what the viewer sees.
#   e.g. iPhone 4K portrait: source=3840x2160, rotation=-90 → display=1080x1920
#
# Usage:
#   bash probe.sh <video_file> [--loudness] [--pretty]
#
#   --loudness   Run EBU R128 integrated-loudness scan (~10 s per 60 s of video).
#                Off by default (adds time; not always needed at intake).
#   --pretty     Pretty-print JSON. Default: compact single line.
#
# Exit codes: 0 success, 1 bad args/file not found, 2 ffprobe/parse error

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
VIDEO_FILE=""
DO_LOUDNESS=0
PRETTY=0

for arg in "$@"; do
  case "$arg" in
    --loudness) DO_LOUDNESS=1 ;;
    --pretty)   PRETTY=1 ;;
    -*)
      echo "Unknown flag: $arg" >&2
      echo "Usage: probe.sh <video_file> [--loudness] [--pretty]" >&2
      exit 1
      ;;
    *)
      VIDEO_FILE="$arg"
      ;;
  esac
done

if [[ -z "$VIDEO_FILE" ]]; then
  echo "Usage: probe.sh <video_file> [--loudness] [--pretty]" >&2
  exit 1
fi

if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "{\"error\": \"File not found: $VIDEO_FILE\"}" >&2
  exit 1
fi

if ! command -v ffprobe &>/dev/null; then
  echo "{\"error\": \"ffprobe not found on PATH\"}" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "{\"error\": \"python3 not found on PATH — needed for JSON parsing\"}" >&2
  exit 1
fi

# Absolute path (important for portability of JSON output)
VIDEO_ABS="$(cd "$(dirname "$VIDEO_FILE")" && pwd)/$(basename "$VIDEO_FILE")"

# ---------------------------------------------------------------------------
# Step 1: ffprobe → raw JSON (all streams + format)
# ---------------------------------------------------------------------------
PROBE_JSON=$(ffprobe \
  -v quiet \
  -print_format json \
  -show_format \
  -show_streams \
  "$VIDEO_ABS" 2>&1) || {
  echo "{\"error\": \"ffprobe failed on: $VIDEO_ABS\"}" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Step 2: Write ffprobe JSON to a temp file, then run Python parser
#         (avoids bash heredoc + pipe interaction; safe for multi-line side_data)
# ---------------------------------------------------------------------------
PROBE_TMP=$(mktemp /tmp/probe_json.XXXXXX)
# shellcheck disable=SC2064
trap "rm -f '$PROBE_TMP'" EXIT
printf '%s' "$PROBE_JSON" > "$PROBE_TMP"

RESULT=$(python3 - "$VIDEO_ABS" "$DO_LOUDNESS" "$PROBE_TMP" <<'PYEOF'
import sys, json, subprocess, os, re

video_abs    = sys.argv[1]
do_loudness  = (sys.argv[2] == "1")
probe_file   = sys.argv[3]

# ── Load ffprobe JSON from temp file ─────────────────────────────────────────
with open(probe_file) as fh:
    raw = fh.read().strip()
try:
    probe = json.loads(raw)
except json.JSONDecodeError as e:
    sys.stdout.write(json.dumps({"error": f"ffprobe JSON parse failed: {e}", "raw": raw[:500]}))
    sys.exit(2)

streams = probe.get("streams", [])
fmt     = probe.get("format", {})

# ── Identify video + audio streams ───────────────────────────────────────────
video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)

if video_stream is None:
    sys.stdout.write(json.dumps({"error": "No video stream found", "file": video_abs}))
    sys.exit(2)

# ── Duration ─────────────────────────────────────────────────────────────────
duration_s = 0.0
for src in (video_stream, fmt):
    if "duration" in src:
        try:
            duration_s = float(src["duration"])
            if duration_s > 0:
                break
        except (ValueError, TypeError):
            pass

# ── FPS ───────────────────────────────────────────────────────────────────────
fps = 0.0
for fps_key in ("r_frame_rate", "avg_frame_rate"):
    val = video_stream.get(fps_key, "")
    if val and "/" in val and val != "0/0":
        try:
            num, den = val.split("/")
            computed = round(float(num) / float(den), 3)
            if computed > 0:
                fps = computed
                break
        except (ValueError, ZeroDivisionError):
            pass

# ── Source (stream-encoded) dimensions ───────────────────────────────────────
source_w = int(video_stream.get("width",  0))
source_h = int(video_stream.get("height", 0))

# ── ROTATION GOTCHA ───────────────────────────────────────────────────────────
# iPhone/Android portrait clips are often stored with rotation metadata.
# A 4K portrait iPhone clip: source stream = 3840×2160, rotation = -90 (or 270)
# → display dimensions = 2160×3840 = 1080×1920 after scaling.
# We detect from two places:
#   1. video_stream["tags"]["rotate"]    — legacy MP4/MOV container tag
#   2. video_stream["side_data_list"]    — modern ISOBMFF Display Matrix
# Rotation values:
#   0   → no swap
#   90  → swap (rotated CCW 90° means portrait encoded as landscape rotated left)
#   -90 → swap (same as 270)
#   180 → no swap (upside down, but same dimensions)
#   270 → swap

rotation_deg = 0

# Method 1: tags.rotate (string, may be negative e.g. "-90")
rotate_tag = str(video_stream.get("tags", {}).get("rotate", "")).strip()
if rotate_tag:
    try:
        rotation_deg = int(rotate_tag)
    except ValueError:
        pass

# Method 2: side_data_list Display Matrix (ffprobe modern output)
if rotation_deg == 0:
    for sd in video_stream.get("side_data_list", []):
        if sd.get("side_data_type", "") == "Display Matrix":
            r = sd.get("rotation", None)
            if r is not None:
                try:
                    rotation_deg = int(round(float(r)))
                except (ValueError, TypeError):
                    pass
            break

# Normalise to [0, 360) for the swap check
rotation_norm = rotation_deg % 360

# Swap w↔h when rotation is ±90 or ±270
display_w, display_h = source_w, source_h
if rotation_norm in (90, 270):
    display_w, display_h = source_h, source_w

# ── Aspect ratio (based on DISPLAY dimensions) ────────────────────────────────
def gcd(a, b):
    while b:
        a, b = b, a % b
    return a

if display_w > 0 and display_h > 0:
    g = gcd(display_w, display_h)
    aspect_ratio = f"{display_w // g}:{display_h // g}"
    # Map to known social-media ratios by float comparison
    ratio_float = display_w / display_h
    KNOWN_RATIOS = [
        (9/16,  "9:16"),
        (16/9,  "16:9"),
        (1/1,   "1:1"),
        (4/5,   "4:5"),
        (5/4,   "5:4"),
        (4/3,   "4:3"),
        (3/4,   "3:4"),
        (3/2,   "3:2"),
        (2/3,   "2:3"),
    ]
    for r_known, label in KNOWN_RATIOS:
        if abs(ratio_float - r_known) < 0.012:
            aspect_ratio = label
            break
else:
    aspect_ratio = "unknown"

# ── Orientation ───────────────────────────────────────────────────────────────
if display_w > display_h:
    orientation = "landscape"
elif display_h > display_w:
    orientation = "portrait"
else:
    orientation = "square"

# ── Codec + container + bitrate ───────────────────────────────────────────────
video_codec   = video_stream.get("codec_name", "unknown")
container     = fmt.get("format_name", "unknown").split(",")[0]
bit_rate_kbps = 0
for src in (fmt, video_stream):
    br = src.get("bit_rate")
    if br:
        try:
            bit_rate_kbps = int(br) // 1000
            break
        except (ValueError, TypeError):
            pass

# ── Color / HDR detection ─────────────────────────────────────────────────────
color_space     = video_stream.get("color_space",     "unknown")
color_primaries = video_stream.get("color_primaries", "unknown")
color_transfer  = video_stream.get("color_transfer",  "unknown")

# HDR: PQ (HDR10/HDR10+), HLG, or SMPTE 428; WCG if just bt2020 primaries
hdr = color_transfer in ("smpte2084", "arib-std-b67", "smpte428") or \
      color_primaries == "bt2020"
hdr_type = None
if color_transfer == "smpte2084":
    hdr_type = "HDR10 / PQ"
elif color_transfer == "arib-std-b67":
    hdr_type = "HLG"
elif color_transfer == "smpte428":
    hdr_type = "SMPTE 428"
elif color_primaries == "bt2020" and color_transfer not in ("smpte2084", "arib-std-b67"):
    hdr_type = "WCG (bt2020 primaries, non-HDR transfer)"

# ── Audio ────────────────────────────────────────────────────────────────────
has_audio   = audio_stream is not None
audio_codec = audio_stream.get("codec_name") if has_audio else None
sample_rate = None
channels    = None
if has_audio:
    try: sample_rate = int(audio_stream.get("sample_rate", 0))
    except (ValueError, TypeError): pass
    try: channels = int(audio_stream.get("channels", 0))
    except (ValueError, TypeError): pass

# ── File size ────────────────────────────────────────────────────────────────
try:
    file_size_mb = round(os.path.getsize(video_abs) / (1024 * 1024), 2)
except OSError:
    file_size_mb = None

# ── Rotation note (human-readable flag) ──────────────────────────────────────
if rotation_deg != 0:
    rotation_note = (
        f"ROTATED: stream encoded as {source_w}x{source_h} "
        f"but displays as {display_w}x{display_h} "
        f"(rotation tag = {rotation_deg} deg)"
    )
else:
    rotation_note = "none"

# ── Optional loudness scan (EBU R128) ────────────────────────────────────────
loudness_lufs    = None
loudness_lra     = None
loudness_tp_dbfs = None

if do_loudness and has_audio:
    try:
        cmd = [
            "ffmpeg", "-nostats", "-hide_banner",
            "-i", video_abs,
            "-af", "ebur128=peak=true",
            "-f", "null", "-"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        stderr = result.stderr

        # Integrated loudness: "    I:     -14.3 LUFS"
        m = re.search(r"\bI:\s*([-\d.]+)\s*LUFS", stderr)
        if m:
            loudness_lufs = float(m.group(1))

        # LRA: "    LRA:    6.3 LU"
        m2 = re.search(r"\bLRA:\s*([-\d.]+)\s*LU\b", stderr)
        if m2:
            loudness_lra = float(m2.group(1))

        # True peak: "    True peak:          -0.4 dBFS"
        m3 = re.search(r"True peak:\s*([-\d.]+)\s*dBFS", stderr)
        if m3:
            loudness_tp_dbfs = float(m3.group(1))

    except Exception as e:
        loudness_lufs = f"error: {e}"

# ── Assemble output ───────────────────────────────────────────────────────────
out = {
    # ── Identity
    "file_path":         video_abs,
    "file_size_mb":      file_size_mb,
    "container":         container,

    # ── Timing
    "duration_s":        round(duration_s, 3),
    "fps":               fps,

    # ── Display geometry (rotation-corrected — use these for routing)
    "display_w":         display_w,
    "display_h":         display_h,
    "aspect":            aspect_ratio,
    "orientation":       orientation,

    # ── Source (stream-encoded) geometry
    "source_w":          source_w,
    "source_h":          source_h,
    "rotation_deg":      rotation_deg,
    "rotation_note":     rotation_note,

    # ── Codec / quality
    "video_codec":       video_codec,
    "bit_rate_kbps":     bit_rate_kbps,
    "color_space":       color_space,
    "color_primaries":   color_primaries,
    "color_transfer":    color_transfer,
    "hdr":               hdr,
    "hdr_type":          hdr_type,

    # ── Audio
    "has_audio":         has_audio,
    "audio_codec":       audio_codec,
    "sample_rate_hz":    sample_rate,
    "channels":          channels,

    # ── Loudness (null if --loudness not passed)
    "loudness_lufs":     loudness_lufs,
    "loudness_lra":      loudness_lra,
    "loudness_tp_dbfs":  loudness_tp_dbfs,
}

sys.stdout.write(json.dumps(out))
PYEOF
)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ "$PRETTY" -eq 1 ]]; then
  if command -v python3 &>/dev/null; then
    echo "$RESULT" | python3 -m json.tool
  elif command -v jq &>/dev/null; then
    echo "$RESULT" | jq .
  else
    echo "$RESULT"
  fi
else
  echo "$RESULT"
fi

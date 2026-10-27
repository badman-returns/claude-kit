# Platform Presets

> Machine-readable + human-readable spec for every delivery platform.
> `package.sh` reads these values from its own inline `case` block (not this file
> at parse time) but this document is the authoritative source both are kept in
> sync with. Update both when a platform changes specs.

---

## Preset table

| Platform key  | Aspect   | Max size      | Max duration | Codec  | Container | Target loudness | Max true-peak | Video bitrate (target) | Audio bitrate |
|---------------|----------|---------------|-------------|--------|-----------|-----------------|--------------|----------------------|---------------|
| `ig_reel`     | 9:16     | 1080×1920     | 90s         | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `yt_shorts`   | 9:16     | 1080×1920     | 60s         | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `tiktok`      | 9:16     | 1080×1920     | 600s        | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `yt_long`     | 16:9     | 1920×1080     | —           | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 12 Mbps              | 192k AAC      |
| `yt_4k`       | 16:9     | 3840×2160     | —           | H.265  | mp4       | −14 LUFS        | −1 dBTP      | 45 Mbps              | 192k AAC      |
| `ig_feed_45`  | 4:5      | 1080×1350     | —           | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `ig_feed_11`  | 1:1      | 1080×1080     | —           | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `x_16_9`      | 16:9     | 1920×1080     | 140s        | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |
| `x_1_1`       | 1:1      | 1200×1200     | 140s        | H.264  | mp4       | −14 LUFS        | −1 dBTP      | 8 Mbps               | 192k AAC      |

**Bitrate notes:** values above are targets for CBR/VBR pass 1. `-maxrate` = 1.2× target,
`-bufsize` = 2× target. These are reasonable social-upload targets; they do NOT represent
official platform encoding specs (those are minimum requirements, not targets). Adjust for
quality-critical deliverables.

---

## `package.sh` parameter blocks (canonical)

These are the shell variable values the `case` block in `package.sh` sets for each key.
If you update a preset here, update `package.sh` too (they're kept in sync by hand).

```
ig_reel / yt_shorts / tiktok:
  W=1080  H=1920  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=8M  MAXRATE=9600k  BUFSIZE=16M  ACODEC=aac  ABITRATE=192k

yt_long:
  W=1920  H=1080  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=12M  MAXRATE=14400k  BUFSIZE=24M  ACODEC=aac  ABITRATE=192k

yt_4k:
  W=3840  H=2160  VCODEC=libx265  PROFILE=main  LEVEL=5.1
  VBITRATE=45M  MAXRATE=54M  BUFSIZE=90M  ACODEC=aac  ABITRATE=192k

ig_feed_45:
  W=1080  H=1350  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=8M  MAXRATE=9600k  BUFSIZE=16M  ACODEC=aac  ABITRATE=192k

ig_feed_11:
  W=1080  H=1080  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=8M  MAXRATE=9600k  BUFSIZE=16M  ACODEC=aac  ABITRATE=192k

x_16_9:
  W=1920  H=1080  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=8M  MAXRATE=9600k  BUFSIZE=16M  ACODEC=aac  ABITRATE=192k

x_1_1:
  W=1200  H=1200  VCODEC=libx264  PROFILE=high  LEVEL=4.0
  VBITRATE=8M  MAXRATE=9600k  BUFSIZE=16M  ACODEC=aac  ABITRATE=192k
```

---

## Loudness policy

All platforms target **−14 LUFS / −1 dBTP** (EBU R128 social standard).

`video-use/render.py` runs **two-pass loudnorm** on `final.mp4` by default.
`package.sh` therefore does NOT re-normalize unless given `--force-loudnorm`.
Instead it runs an **ebur128 measurement** and prints integrated LUFS as a sanity check.
If the measured value is outside [−16, −12] LUFS, it warns but does not fail.

---

## Aspect-ratio reframe policy

If `final.mp4`'s native aspect does not match the target platform's, `package.sh`
applies a **pad** (letterbox/pillarbox) rather than a crop, unless the director
explicitly passes `--reframe-crop`. This is conservative: pad preserves framing;
crop can cut off subjects.

Padding color default: `#000000` (black). Pass `--pad-color <hex>` to change.

---

## HDR note

`video-use/render.py` already tonemaps HDR to Rec.709 SDR per segment.
`final.mp4` should arrive at `package.sh` as SDR. If it arrives HDR
(i.e., `--no-loudnorm` was used and render.py's HDR path ran),
`package.sh` will detect HLG/PQ colorspace via ffprobe and apply
`zscale+tonemap` before encoding. See `package.sh` HDR path comment.

# Routing Matrix — Pipelines

> Every row maps an intent/step to a **real command or an explicit ⚠ flag**.
> No row silently routes to vapor. Legend: **✓ video-use** · **⚙ ffmpeg** ·
> **⚙+venv ffmpeg + director venv** · **⚠ not built / deferred**.

---

## Capability matrix

| Step | Status | Script / tool | Command shape |
|------|--------|---------------|---------------|
| Transcription · silence-trim cuts · grade · overlays / motion gfx · subtitles · loudness (−14 LUFS two-pass) | ✓ video-use | video-use edit phase | (baton — video-use owns) |
| Reframe → 9:16, safe-crop (center) | ⚙ `prep.sh` | `ffmpeg crop+scale` | `crop=ih*9/16:ih,scale=1080:1920` |
| Reframe → 9:16, AI subject-tracking | ⚠ DEFERRED | — | Needs ML (autoflip / mediapipe). Use safe-crop until v2. |
| Stabilize (vidstab, 2-pass) | ⚙ `prep.sh` | `ffmpeg -vf vidstabdetect` then `vidstabtransform` | Pass 1: writes `.trf`; Pass 2: applies transform |
| Background removal (video) | ⚙+venv `prep.sh` | `backgroundremover` CLI (py3.11 `~/.video-director-venv`) | `backgroundremover -i <in> -o <out>` |
| Platform-correct encode (aspect / codec / bitrate) | ⚙ `package.sh` | `ffmpeg libx264/libx265` | See `platform-presets.md` case block |
| Loudness verify (measure only, post-render.py) | ⚙ `package.sh` | `ffmpeg -vf ebur128` | Measures LUFS; warns if outside [−16, −12]; does NOT re-normalize by default |
| Loudness re-normalize (explicit `--force-loudnorm`) | ⚙ `package.sh` | `ffmpeg loudnorm` two-pass | Only when caller explicitly opts in (non-video-use input) |
| Aspect-ratio pad (letterbox / pillarbox) | ⚙ `package.sh` | `ffmpeg pad` | Default for aspect mismatch; use `--reframe-crop` for crop |
| edl.json → OTIO → edit.fcpxml | ⚙+venv `handoff.sh` | `opentimelineio` (py3.11 `~/.video-director-venv`) | `otio.adapters.write_to_file(tl, "edit.fcpxml")` |
| Music bed (mix under edit) | ⚠ NOT WIRED | — | Needs music-source folder/API (open Q). `amix`+`loudnorm` are available in ffmpeg once source is defined. |
| Beat-synced cuts | ⚠ DEFERRED v2 | — | Needs beat detection (`aubio`/`librosa`). Defer. |
| B-roll inserts | ⚠ MANUAL | — | Editorial decision — handle inside video-use manually. |
| Zoom-emphasis (`zoompan`) | ⚙ video-use overlay | `ffmpeg zoompan` | Available in ffmpeg; can be a video-use overlay or prep step. |

---

## Seed pipelines

Each pipeline is an ordered list of the steps above.
Steps before `[baton]` run in `prep.sh`; after `[baton]` run inside video-use.

### Phone → Instagram Reel → punchy

```
1. reframe safe-crop → 9:16                     (prep.sh · ⚙)
2. stabilize (vidstab 2-pass)                    (prep.sh · ⚙)
   ── [baton to video-use] ──
3. silence-trim cuts                              (video-use · ✓)
4. captions                                       (video-use · ✓)
5. grade (warm_cinematic or auto)                 (video-use · ✓)
6. loudness −14 LUFS (already in render.py)       (video-use · ✓)
   ── [POST] ──
7. platform encode → ig_reel                      (package.sh · ⚙)
8. [opt] edit.fcpxml for DaVinci                  (handoff.sh · ⚙+venv)
```

### OBS capture → YouTube → tutorial

```
1. background removal (backgroundremover)         (prep.sh · ⚙+venv)
   ── [baton to video-use] ──
2. lower-thirds overlay (HyperFrames/PIL)         (video-use · ✓)
3. zoom-emphasis (zoompan)                        (video-use · ✓)
4. chapter markers + captions                     (video-use · ✓)
5. grade (neutral_punch)                          (video-use · ✓)
6. loudness −14 LUFS                              (video-use · ✓)
   ── [POST] ──
7. platform encode → yt_long or yt_4k             (package.sh · ⚙)
8. [opt] edit.fcpxml                              (handoff.sh · ⚙+venv)
```

### Phone → YouTube → cinematic vlog

```
1. stabilize (vidstab 2-pass)                     (prep.sh · ⚙)
   ── [baton to video-use] ──
2. grade (LUT / warm_cinematic)                   (video-use · ✓)
3. titles overlay (HyperFrames or Remotion)       (video-use · ✓)
4. loudness −14 LUFS                              (video-use · ✓)
   ── [POST] ──
5. platform encode → yt_long                      (package.sh · ⚙)
8. [opt] edit.fcpxml                              (handoff.sh · ⚙+venv)
```

### Screen recording → explainer

```
(no prep.sh steps needed — screen recs are already stable, 16:9, no bg removal)
   ── [baton to video-use] ──
1. Manim/overlay animations (render.py sub-agents) (video-use · ✓)
2. zoom-emphasis (zoompan)                         (video-use · ✓)
3. captions                                        (video-use · ✓)
4. loudness −14 LUFS                              (video-use · ✓)
   ── [POST] ──
5. platform encode → yt_long or yt_shorts          (package.sh · ⚙)
6. [opt] edit.fcpxml                               (handoff.sh · ⚙+venv)
```

---

## ⚠ Rows with no real command behind them (v1 limits)

| Row | Status | Notes |
|-----|--------|-------|
| AI subject-tracking reframe | ⚠ DEFERRED | Use safe-crop. v2 will need autoflip/mediapipe. |
| Beat-synced cuts | ⚠ DEFERRED v2 | Needs `aubio` or `librosa` beat detection. |
| B-roll inserts | ⚠ MANUAL | Not auto-insertable; handled inside video-use conversationally. |
| Music bed | ⚠ NOT WIRED | `amix` and `loudnorm` in ffmpeg are ready; missing music-source directory or API. Open question, not defaulted. |

---

## Routing decision (intake → pipeline)

The director picks a seed pipeline at intake based on:

| Source type | Platform | → Seed pipeline |
|-------------|----------|----------------|
| Phone (portrait/landscape) | IG Reel / Shorts / TikTok | Phone → IG Reel → punchy |
| OBS / screen cap | YouTube | OBS → YouTube → tutorial |
| Phone (landscape) | YouTube | Phone → YouTube → cinematic vlog |
| Screen recording | YouTube / any | Screen rec → explainer |

The director may combine steps (e.g. stabilize + bg-removal for a handheld OBS setup).

# Video Director — Build Spec (v2, validated)

> A global Claude Code skill that acts as a **video director**: takes any source
> (phone clip, OBS capture, screen recording), understands content + platform +
> intent, then runs the right pipeline through a stage-gated conversation —
> handing the actual editing to `video-use` via a clean baton-pass.

**Status:** spec validated · build not yet started
**Runtime:** Claude Code on macOS (local execution required)
**Machine (probed 2026-06-26):** arm64 · ffmpeg 8.1.2 (full build) · node v22 ·
Python 3.14.6 · pipx · brew · OBS.app installed · `video-use` + `prompt-architect` skills present

---

## ⚠️ Validation findings folded into this v2

Three parallel validation agents + an architecture review changed four things from v1:

1. **Architecture pivot — A vs B → take B (baton-pass).** `video-use` is NOT a
   passive editing library; it is a self-driving conversational editor with its own
   ask→confirm→iterate loop, intake, self-eval, and the 12 correctness rules. And
   skill→skill delegation has **no enforcement mechanism** (it's advisory — Claude
   *may* invoke). So the director does **not** drive video-use as a subroutine.
   Instead: **director owns PRE + POST, video-use owns the EDIT.** (See §1.)
2. **Python 3.14 breaks the ML half.** rembg, backgroundremover, and Manim do **not**
   install cleanly on 3.14.6 (onnxruntime/torch/dearpygui lack 3.14 wheels as of
   Jun 2026). → ML tools run in a dedicated **Python 3.11/3.12 venv**, never system 3.14.
3. **rembg ≠ video.** rembg is image-only (video = manual frame pipe). Native video
   background removal = **`backgroundremover`** CLI. Spec corrected.
4. **SVD / AnimateDiff are CUDA-preferred and fragile on Apple Silicon (MPS).**
   Deferred to "optional / experimental" — not part of the core arm64 pipeline.

Bonus: `video-use` **already** owns motion graphics (Remotion / Manim / HyperFrames
overlays via parallel sub-agents in its `render.py`). The director does **not** wire
a separate motion-graphics layer — it's inside the edit phase.

---

## 1. Architecture — the baton-pass (Option B)

```
   ┌─────────────────────────────────────────────────────────────┐
   │  DIRECTOR  (~/.claude/skills/video-director/)                 │
   │                                                               │
   │   PRE                                          POST           │
   │   • intake interview      ──── baton ────►     • platform     │
   │   • intent → routing                            packaging     │
   │   • ffprobe the source                          (aspect/codec/│
   │   • prep source (venv tools:                    bitrate/LUFS) │
   │     bg-removal, reframe, stabilize)             • variations  │
   └───────────────────┬──────────────────────────▲──────────────┘
                       │ hands gathered context     │ returns finished
                       │ (platform, intent,         │ edit/ output
                       ▼ duration, vibe, file)      │
   ┌─────────────────────────────────────────────────────────────┐
   │  video-use  — owns THE EDIT (its own ask→confirm→iterate loop)│
   │  transcription · cuts · grade · overlays/motion gfx · subs    │
   │  · loudness · self-eval · edl.json · the 12 correctness rules │
   └─────────────────────────────────────────────────────────────┘
```

**The principle:** control is **sequenced, never concurrent.** The director and
video-use never both try to drive the conversation at the same time. The director
gathers context up front, passes the baton (so video-use doesn't re-ask intake),
video-use runs the edit with its proven loop, then the baton returns for packaging.

**Why B over A (calling video-use's helper scripts directly):** A would force the
director to re-implement edl.json authoring + the 12 correctness rules + craft
heuristics — making it a *thick* director that drifts out of sync as video-use
evolves. Critically, several correctness rules live in video-use's **SKILL.md prose**,
not its code; bypassing the skill silently loses them. B keeps them because video-use
itself still runs the edit. Being a "wrapper" is the thin-director design, not a flaw.

**The seam to get right:** since skill→skill is advisory, the director can't
*guarantee* video-use fires. The director's SKILL.md must (a) explicitly instruct
invoking video-use at the baton point and (b) write the gathered context to a
handoff file video-use reads (`project.md` / `SESSION-HANDOFF.md` — its existing
session-memory convention) so the context survives even if invocation is manual.

---

## 2. File tree

```
~/.claude/skills/video-director/
├── SKILL.md                    # PRE + POST workflow, baton-pass, stage-gates
├── SPEC.md                     # this doc
├── STRATEGY.md                 # multi-agent build plan
├── scripts/
│   ├── doctor.sh               # readiness report (incl. venv + filter checks)
│   ├── install.sh              # idempotent; provisions py3.11 venv for ML tools
│   ├── probe.sh                # ffprobe → normalized JSON
│   ├── prep.sh                 # PRE source-prep: reframe / stabilize / bg-removal
│   └── package.sh              # POST: platform-correct final encode
└── references/
    ├── pipelines.md            # routing matrix (intent → steps), capability-tagged
    ├── platform-presets.md     # YT / IG / TikTok / X specs
    ├── motion-engines.md       # overlay engine selector (HyperFrames/Remotion/Manim/…)
    ├── preview-and-handoff.md  # timeline.html viewer + OTIO→DaVinci (FCPXML) export
    └── baton-handoff.md        # exact context the director passes to video-use (was handoff.md)
```

Reference bundled scripts from SKILL.md with `${CLAUDE_SKILL_DIR}/scripts/<x>`.

---

## 3. Routing matrix (`references/pipelines.md`) — capability-tagged

Legend: **✓ in video-use** · **⚙ ffmpeg (confirmed in your build)** · **⚠ needs new tooling**

| Step | Status | How |
|------|--------|-----|
| transcription / cuts / grade / overlays / subtitles / loudness | ✓ | video-use (edit phase) |
| reframe → 9:16 (center/safe-crop) | ⚙ | `crop`,`scale` — PRE via `prep.sh` |
| reframe → 9:16 (AI subject-tracking) | ⚠ | needs ML (e.g. autoflip); **defer**, use safe-crop v1 |
| stabilize | ⚙ | `vidstabdetect`+`vidstabtransform` (present) — PRE |
| zoom-emphasis | ⚙ | `zoompan` (present) — can be a video-use overlay or PRE |
| background removal | ⚙+venv | `backgroundremover` CLI (py3.11 venv) — PRE |
| music bed | ⚙ | `amix`/`loudnorm` — needs a **music source folder** (open Q) |
| beat-synced cuts | ⚠ | needs beat detection (`aubio`/`librosa`) — **defer to v2** |
| b-roll inserts | ⚠ | an editorial decision, not auto — handle inside video-use manually |

PRE steps (⚙ + bg-removal) run in `prep.sh` before the baton pass. Editorial steps
(cuts/grade/overlays/subs) are video-use's. Mark ⚠ rows explicitly as not-yet-built
in v1 so the matrix never routes to vapor.

**Seed pipelines** (each = an ordered list of the above):
- Phone → IG Reel → punchy: `reframe(crop)` · `stabilize` → [baton] → silence-trim cuts · captions · grade · loudness
- OBS → YouTube → tutorial: `bg-removal` → [baton] → lower-thirds · zoom-emphasis · chapters · captions · grade
- Phone → YouTube → cinematic vlog: `stabilize` → [baton] → grade(LUT) · titles · loudness
- Screen rec → explainer: → [baton] → Manim/overlay animations · zoom-emphasis · captions

---

## 4. Platform presets (`references/platform-presets.md`)

| Platform | Aspect | Max len | Codec | Container | Loudness |
|----------|--------|---------|-------|-----------|----------|
| YouTube | 16:9 (1080p/4K) | — | H.264/HEVC | mp4 | -14 LUFS |
| YouTube Shorts | 9:16 | 60s | H.264 | mp4 | -14 LUFS |
| Instagram Reel | 9:16 (1080×1920) | 90s | H.264 | mp4 | -14 LUFS |
| Instagram Feed | 4:5 or 1:1 | — | H.264 | mp4 | -14 LUFS |
| TikTok | 9:16 | 10min | H.264 | mp4 | -14 LUFS |
| X / Twitter | 16:9 or 1:1 | — | H.264 | mp4 | -14 LUFS |

`package.sh` reads this; loudness via `loudnorm` (confirmed in your ffmpeg).

---

## 5. Environment bootstrap (Layer 0)

**Already present:** ffmpeg 8.1.2 (full — vidstab/zoompan/loudnorm/lut3d/haldclut all
compiled in), node v22, python 3.14, pipx, brew, OBS.app, yt-dlp.

**`install.sh` must:**
- Provision a **dedicated Python 3.11 venv** (e.g. `~/.video-director-venv`) and
  install the ML tools there — **never** system 3.14:
  - `backgroundremover` (native video bg-removal)
  - `manim` *(optional — video-use already vendors it; only if standalone needed)*
- Register obs-mcp at **user scope**:
  ```bash
  claude mcp add --scope user --transport stdio obs -- npx -y obs-mcp
  ```
  Requires OBS → Tools → WebSocket Server Settings → enable (note port/password).
- **Deferred / experimental (not installed by default):** Stable Video Diffusion,
  AnimateDiff — CUDA-preferred, fragile on MPS. Flag, don't install.

**`doctor.sh`** prints readiness incl. venv health and the ffmpeg-filter check.

---

## 6. Contract discovery (the build linchpin — do FIRST)

Before any component is written, one agent must map the **baton boundary** exactly:
- `video-use` invocation: how it's triggered, what it reads at start (`project.md` /
  `SESSION-HANDOFF.md` schema), what context it will accept to skip re-asking intake.
- Its output contract: where finished files land (`<videos_dir>/edit/`), the `edl.json`
  shape (read-only reference for the director).
- **Which of the 12 correctness rules live in code (`render.py` etc.) vs. SKILL.md
  prose** — the prose ones are exactly what B preserves and A would lose.

Output = `references/baton-handoff.md`. Everything else builds against it.

---

## 7. Build phases & acceptance

| Phase | Deliverable | Done when… |
|-------|-------------|-----------|
| **0. Contract discovery** | `handoff.md` | baton boundary + handoff file format pinned |
| **1. Environment** | `doctor.sh`, `install.sh` (py3.11 venv), obs registered | clean machine → ready; `doctor.sh` green |
| **2. Skill skeleton** | `SKILL.md` (PRE + baton + POST + gates) | runs on a real clip: intake→probe→prep→hands to video-use→packages |
| **3. Recipes + PRE** | `pipelines.md`, `platform-presets.md`, `prep.sh`, `package.sh` | every matrix row maps to a real command or is flagged ⚠ |
| **4. Live capture** | obs wired into intake | "record my tutorial" → file flows into director |
| **5. Preview/handoff** | OTIO→FCPXML exporter (`handoff.sh`); POST offers viewer vs DaVinci | `edit.fcpxml` opens the cut in DaVinci as a real timeline |
| **6. Polish** | tuned from real projects | 3 videos shipped end-to-end |

**Open questions:** (1) music source folder/API; (2) AI reframe — defer or build;
(3) resumable `project.json` for cross-session edits (recommend yes — video-use
already has session memory to lean on).

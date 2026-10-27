# Video Director — Manual

> A manual for **both humans and Claude**. A human reads it to learn how to drive
> the skill. Claude reads it (alongside `SKILL.md`) when guiding someone through an
> edit. `SKILL.md` is the operating procedure; this is the orientation, the
> decision guide, and a worked example. Where they overlap, `SKILL.md` is law.

---

## What this skill does

You hand it raw footage and a destination — "make this a reel", "cut this for
YouTube" — and it turns the footage into a platform-ready file. It is a **director**,
not an editor: it figures out what the video should be and ships it, and hands the
actual cutting/grading/captioning to the **`video-use`** skill.

Think of it as three acts with two baton-passes:

```
   PRE  ──baton──►  THE EDIT  ──baton──►  POST
  (director)       (video-use)          (director)
```

- **PRE** (director): interview you, probe the footage, pick a pipeline, prep the
  source (reframe / stabilize / background-removal).
- **THE EDIT** (`video-use`): transcribe, cut, grade, caption, add motion graphics,
  normalize loudness — its own `ask → confirm → iterate` loop.
- **POST** (director): encode to the exact platform spec, make variations, hand off
  to a preview viewer or to DaVinci Resolve.

**When to use the director vs. `video-use` directly:** if you name a platform and a
deliverable ("turn this into a Reel"), use the director — it wraps the edit for that
target. If you just want to fiddle with a cut and don't care about packaging, you can
talk to `video-use` directly.

---

## Quickstart

1. **Drop your footage** somewhere you can point to — e.g.
   `~/Documents/Instagram Content/raw/IMG_3091.MOV`. The director writes all outputs
   to `<that folder>/edit/` and never touches your raw file.
2. **Invoke the director** by describing the job: *"Make IMG_3091.MOV into a 9:16
   Instagram Reel, punchy, under 90 seconds."* (Or type `/video-director`.)
3. **Answer the brief** (source, platform, intent, vibe, length).
4. **Approve each gate** — the director shows proof (a frame, a pipeline, specs) and
   waits for your OK before moving on.
5. At the baton point it **hands to `video-use`** for the edit; you confirm the cut
   there.
6. Back in the director, it **packages** the final file and offers a preview or a
   DaVinci timeline.

**Live capture (optional):** if OBS is set up (see Troubleshooting), you can say
"record my tutorial" and the director drives OBS to capture, then flows the file
into PRE.

---

## The 12-step flow at a glance (YOU / AI / GATE)

Every **GATE** = the director shows proof and waits for your explicit OK.

| # | Act | Who | What happens |
|:-:|-----|-----|--------------|
| 1 | PRE | **YOU** | Drop footage + brief: source, platform, intent, vibe, length |
| 2 | PRE | AI | Readiness check + probe every source |
| 3 | PRE | AI | Pick a pipeline, propose it — **GATE** |
| 4 | PRE | AI | Reframe / stabilize / bg-removal, show proof — **GATE** |
| 5 | PRE | AI | Write the brief into `edit/project.md` (the baton file) |
| 6 | **BATON** | AI | **Invoke `video-use`** ═══► |
| 7 | EDIT | video-use | Transcribe → propose strategy → confirm (its gate) |
| 8 | EDIT | video-use | Cut → render → self-eval → preview → iterate (its gate) |
| 9 | EDIT | video-use | Final render → `edit/final.mp4` ◄═══ baton returns |
| 10 | POST | AI | Package to platform spec — **GATE** |
| 11 | POST | AI | Variations for other platforms/aspects |
| 12 | POST | AI | Offer scrub-preview vs DaVinci handoff — **GATE** |

The two **baton crossings** (steps 5→6 and 9→10) are the whole design: the director
and `video-use` are never both steering at once.

---

## How to brief well

The director needs five things. The clearer you are, the fewer questions it asks.

| Field | What it sets | Good answers |
|-------|--------------|--------------|
| **Source** | the footage | a file path, several clips, or "record it now" |
| **Platform** | aspect, max length, codec, loudness | YouTube, Shorts, IG Reel, IG Feed, TikTok, X |
| **Intent** | the narrative shape | launch/demo, tutorial, vlog, explainer, interview, montage |
| **Vibe / reference** | grade + motion style | "punchy", "cinematic", a brand palette, a link to match |
| **Length** | target runtime | "under 60s", "about 90s" (platform cap also applies) |

A strong one-liner: *"Phone clip `IMG_3091.MOV` → Instagram Reel, 9:16, dev war-story,
punchy and brand-matched to my blog, under 90s."* That alone routes a pipeline.

---

## Where your input matters most (the decision points)

Most steps are mechanical. Four are genuinely yours — spend your attention here:

1. **The narrative cut.** Which beats stay, in what order, where to start and end.
   This happens inside `video-use` (step 7–8) when it proposes a strategy. Read it
   and push back — this is the single highest-leverage decision.
2. **The grade.** Direction, not numbers: cool/punchy, warm/cinematic, neutral, or
   none. You set the *direction* in the brief; `video-use` executes it.
3. **The motion engine.** If overlays/diagrams are involved, *what they should look
   like* picks the engine (see the options menu). Brand-matched UI → HyperFrames;
   math → Manim; data/charts → Remotion.
4. **Captions.** Chunking (1–2 words vs sentences), case (UPPER vs natural), and
   placement. Defaults are social-optimized (see gotchas) but this is taste.

---

## The options menu

### Platforms (`references/platform-presets.md`)
| Platform | Aspect | Max len | Loudness |
|----------|--------|---------|----------|
| YouTube | 16:9 | — | −14 LUFS |
| YouTube Shorts | 9:16 | 60s | −14 LUFS |
| Instagram Reel | 9:16 (1080×1920) | 90s | −14 LUFS |
| Instagram Feed | 4:5 / 1:1 | — | −14 LUFS |
| TikTok | 9:16 | 10min | −14 LUFS |
| X / Twitter | 16:9 / 1:1 | — | −14 LUFS |

### Grade presets (set the *direction*; `video-use` applies it)
The four presets in `video-use`'s `grade.py`:
- **neutral_punch** — contrast bump + gentle S-curve, no hue shift. Corrective, safe.
- **cool_punch** — same punch with a cool lean. Good for screen/tech content.
- **warm_cinematic** — subtle teal/orange split, slightly desaturated, filmic.
- **none** — straight, no grade.
- Or describe any look in words — `video-use` can build a custom chain (and has an
  auto per-clip mode).

### Motion engines (`references/motion-engines.md`) — pick by what the overlay must SHOW
| Overlay shows… | Engine |
|---|---|
| How data flows through a system; brand-matched UI | **HyperFrames** (CSS = exact brand hex) |
| Math, an algorithm, a graph being drawn | **Manim** |
| Numbers / charts / live data | **Remotion** |
| The same card in N personalized variations | **Remotion / Revideo** |
| A designer's pre-made `.json` animation | **Lottie** (in Remotion) |
| A rotating 3D product | **Blender** (heavy) |
| A quick text card / lower-third | **PIL** or HyperFrames |

Want options on a key beat? Ask for a **bake-off** — render one slot in two engines
and pick.

### Review & handoff (`references/preview-and-handoff.md`)
- **Scrub preview** — a clickable timeline at `localhost:8777` to watch/scrub (not
  edit). Fast review.
- **DaVinci handoff** — `edit.fcpxml` opens the cut as a real multi-track timeline in
  Resolve, where you drag/trim/tweak by hand. Use when you want manual control.

---

## Troubleshooting & gotchas

- **Subtitle burn fails / no captions appear.** You need **`ffmpeg-full`** (it ships
  `libass`); the slim `ffmpeg` can't burn subtitles. After a `brew upgrade`:
  `brew link --overwrite ffmpeg-full`.
- **ML tools (background removal, etc.) won't install.** They run in a **dedicated
  Python 3.11 venv** that `install.sh` provisions — **never** system Python 3.14
  (no wheels for it). If `doctor.sh` shows the venv red, re-run `install.sh`.
- **Phone footage looks sideways / wrong dimensions.** Phone clips are often stored
  landscape (e.g. 3840×2160) with a **rotation flag** (−90°) that makes them *display*
  portrait (1080×1920). `probe.sh` reads the rotation side-data and reports the true
  display orientation; `video-use`'s `render.py` has the `is_portrait_source()` patch
  that swaps width/height when rotation is ±90/270. If a tool ever ignores rotation,
  that's the bug to look for.
- **Captions sit under the platform's UI.** Caption `MarginV=80` is a **safe-zone
  rule**, not taste — it clears the IG/TikTok/Shorts bottom UI band. Don't drop below
  ~75.
- **The audio sounds re-compressed / too loud after packaging.** `final.mp4` is
  *already* normalized to −14 LUFS by `video-use`. POST must **not** loudnorm again —
  if you hear pumping, something double-normalized. POST is container/aspect/codec only.
- **`video-use` didn't auto-start at the baton.** Skill→skill is advisory. The brief
  is already written to `<videos_dir>/edit/project.md`; just invoke `video-use` on the
  footage folder and it reads the brief on startup.
- **OBS capture tools missing.** The `obs` MCP tools only exist after `install.sh`
  registers obs-mcp at user scope and you enable OBS → Tools → WebSocket Server.
  Until then, record manually and drop the file in.

---

## Worked example — the IMG_3091 Instagram Reel

A real reel shipped through this exact flow. Footage:
`~/Documents/Instagram Content/raw/IMG_3091.MOV` — a dev war-story about a bug where
AI-generated table data vanished on page change.

**PRE.**
- *Brief:* phone clip → **Instagram Reel**, 9:16, dev war-story, punchy, blog-matched,
  under 90s.
- *Probe:* source is **4K HEVC, 3840×2160 with rotation = −90°** → displays as
  **1080×1920 portrait**, 176s @30fps, stereo 48kHz. The rotation flag is exactly the
  gotcha above — caught at probe so it never produced a sideways cut.
- *Route:* phone → IG Reel → punchy pipeline. The source already displays 9:16, so no
  crop-reframe was needed; no stabilize (tripod).
- *Baton file:* a `project.md` session block carried the brief — platform, 9:16,
  punchy/blog-matched, grade direction, caption style, and where diagrams should land —
  phrased as a directive so `video-use` went straight to cutting.

**THE EDIT (`video-use`).**
- Transcribed (cached), then cut **176s of raw down to a ~93s, 14-range** narrative:
  HOOK → READ → BUG → ORDER → FIX → LESSON → PUNCHLINE → CTA.
- Grade: **`cool_punch`** (contrast/S-curve, cool, no big hue shift) — matched the
  punchy brief.
- Motion graphics: **HyperFrames** diagrams (THE READ PATH / THE BUG / THE FIX, plus
  THE ORDER / THE PATH) — chosen because they show *how data flows through a system*
  and were **brand-matched to the blog palette** (lime `#CDFF52` flow paths, amber
  `#e7b84a` warnings, on a `#0d0d0d` canvas). Rendered as overlay clips and slotted at
  their output offsets.
- Captions: bold **2-word UPPERCASE** chunks, Helvetica, white-on-outline,
  **`MarginV=80`** (IG safe zone).
- Loudness: **−14 LUFS / −1 dBTP** baked in by `render.py`.
- Output: `raw/edit/final.mp4`, 1080×1920, ~93.5s — applied subtitles last, over the
  overlays, so nothing hid the captions.

**POST.**
- Package step verified it already met the IG Reel spec (9:16, under 90s window,
  H.264/mp4, −14 LUFS) — a container/codec confirm, **no second grade, no second
  loudnorm**.
- Offered the scrub preview (`localhost:8777`) for a final watch and an `edit.fcpxml`
  for DaVinci if hand-tweaks were wanted.

**The lesson the example teaches:** the director caught the orientation flag and set
the brief; `video-use` made every editorial call (which beats, the grade, the diagram
engine, the caption rhythm); the director shipped it without re-touching the picture.
That division — director picks the bookends, `video-use` owns the edit — is the whole
skill.

# Baton Handoff — the video-use contract (Phase 0, the build linchpin)

> Everything downstream (env, PRE/POST scripts, SKILL.md) builds against this file.
> It maps the exact seam where the **director** (PRE + POST) hands control to
> **video-use** (THE EDIT) and gets it back. Architecture = Option B (SPEC §1):
> control is **sequenced, never concurrent**. Source of truth for this map:
> `~/Documents/creative/video-use/{SKILL.md, SESSION-HANDOFF.md, GUIDE.md, helpers/*.py}`.

**Where code diverges from prose, CODE WINS.** Several values in video-use's
SKILL.md prose are stale relative to its shipping helpers. The director must build
to the code. Divergences are flagged inline below.

---

## 1. How video-use is invoked

- video-use is a **Claude Code skill** at `~/.claude/skills/video-use/` (symlinked
  from `~/Documents/creative/video-use/`). It is triggered the normal skill way:
  the model invokes it when the conversation is about editing a video. **There is no
  programmatic entrypoint and no enforcement** — skill→skill delegation is advisory
  (SPEC §1). The director cannot *guarantee* video-use fires.
- Practical consequence for the baton: the director's SKILL.md must (a) explicitly
  instruct "now invoke the `video-use` skill", AND (b) leave the gathered context in
  a file video-use reads on its own, so context survives even if the human re-invokes
  manually. See §2.
- Helpers are **never invoked by the director directly** (that would be Option A).
  They are listed here read-only so the director understands what video-use will do.
- **Local invocation rule (this machine):** there is no bare `python` on PATH. video-use
  helpers run via its own venv: `~/Documents/creative/video-use/.venv/bin/python`
  (Python 3.11 — *separate* from the director's `~/.video-director-venv`; do not conflate).

## 2. What context video-use reads at start (pre-fill this to skip re-asking intake)

video-use has a session-memory convention. Two files matter, and they are NOT equal:

| File | Auto-read by video-use? | Role | Director action |
|------|:---:|------|-----------------|
| `<videos_dir>/edit/project.md` | **YES** — SKILL.md "Memory" §: *"On startup, read `project.md` if it exists and summarize the last session before asking whether to continue."* | Per-session memory log | **Pre-fill this.** This is the baton file. |
| `<repo>/SESSION-HANDOFF.md` | **NO** — manual onboarding doc for a fresh human/session | Style + next-task brief | Read it yourself for style cues; do not rely on video-use reading it. |

**The baton file is `<videos_dir>/edit/project.md`.** Before invoking video-use, the
director writes a session block there with the intake it already gathered, so video-use
reads it instead of re-interviewing. project.md schema (from SKILL.md "Memory"):

```markdown
## Session N — YYYY-MM-DD

**Strategy:** one paragraph describing the approach
**Decisions:** take choices, cuts, grades, animations + why
**Reasoning log:** one-line rationale for non-obvious decisions
**Outstanding:** deferred items
```

The director should pre-seed a block carrying the PRE-phase intake — at minimum:
**platform + target aspect/length, content type, intent/vibe, source file path(s) (and
any prepped/reframed/stabilized variants), grade direction, caption needs, must-keep /
must-cut moments.** Phrase it as a directive ("Strategy: …") so video-use treats it as
the confirmed plan and goes straight to cutting.

> **"Skip re-asking intake" is achieved by convention, not enforcement.** Pre-filling
> project.md makes re-interview *unnecessary*; it cannot make it *impossible*. The
> director's prose should tell video-use the intake is already captured in project.md.

## 3. Where video-use writes output (the `edit/` convention)

All session outputs land in **`<videos_dir>/edit/`** — never inside the video-use repo
(Rule 12). `<videos_dir>` is the folder containing the source footage.

```
<videos_dir>/
├── <source files, untouched>          ← raw stays raw
└── edit/
    ├── project.md            ← memory / BATON FILE (director pre-fills)
    ├── takes_packed.md       ← phrase-level transcript (LLM's reading view)
    ├── edl.json              ← cut decisions (read-only ref for director, §4)
    ├── transcripts/<name>.json
    ├── animations/slot_<id>/ ← per-overlay source + render.mp4/.webm
    ├── clips_graded/         ← per-segment extracts (grade + fades baked)
    ├── master.srt            ← output-timeline subtitles
    ├── verify/ · downloads/
    ├── base.mp4 · preview.mp4 · final.mp4
```

POST handoff implication: the director's `package.sh` reads `<videos_dir>/edit/final.mp4`
(or `preview.mp4`) as its input and writes platform variants elsewhere (scratch / a
`deliver/` dir) — it must not overwrite video-use's `edit/` artifacts.

## 4. `edl.json` shape — READ-ONLY reference

The director never authors this (that's video-use's job, via `render.py` as the consumer).
Shown so the director can *read* a cut and so the OTIO→FCPXML exporter knows the schema.
**`render.py` is a pure EDL consumer** — it executes a finished EDL, it does not author one.
This is why all authoring/conversation rules are prose-only (§5).

```json
{
  "version": 1,
  "sources": {"C0103": "/abs/path/C0103.MP4", "C0108": "/abs/path/C0108.MP4"},
  "ranges": [
    {"source": "C0103", "start": 2.42, "end": 6.85,
     "beat": "HOOK", "quote": "...", "reason": "..."}
  ],
  "grade": "warm_cinematic",
  "overlays": [
    {"file": "edit/animations/slot_1/render.mp4", "start_in_output": 0.0, "duration": 5.0}
  ],
  "subtitles": "edit/master.srt",
  "flashes": [ {"time": 12.40, "color": "white"} ],
  "total_duration_s": 87.4
}
```

Fields render.py actually consumes (some omitted from SKILL.md's example — **code wins**):
- `sources` — name→abs path (relative paths resolve against `edit/`).
- `ranges[]` — `start`/`end` in **source** seconds; `beat`/`quote`/`reason` are metadata.
- `grade` — preset name (`warm_cinematic`, `neutral_punch`, `none`), a **raw ffmpeg
  filter string**, or the sentinel **`"auto"`** (per-segment auto-grade). Bare identifiers
  → preset lookup; anything with `=`/`,` → raw filter.
- `overlays[]` — `{file, start_in_output, duration}`; file = a rendered clip at frame size.
- `subtitles` — path (optional); applied LAST.
- `flashes[]` — `{time, color}` 2-frame flash cuts on the output timeline (not in SKILL.md
  example, but read by render.py).
- `total_duration_s` — informational.

## 5. The 12 correctness rules — CODE-ENFORCED vs PROSE-ONLY (the Option-B justification)

**The linchpin distinction:** `render.py` is a pure EDL *consumer*. Rules about
executing a finished EDL live in its code and survive any path. Rules about *authoring*
the EDL or *running the conversation* exist only in SKILL.md prose — **bypassing the
skill (Option A) would silently lose them.** Option B keeps the prose rules because
video-use itself still runs the edit. Two rules are genuinely **HYBRID** (code does part,
prose/external dependency does the rest) — do not collapse them into the binary.

| # | Rule (abbrev.) | Tag | Lives in |
|:-:|----------------|-----|----------|
| 1 | Subtitles applied LAST in filter chain | **CODE** | `render.py build_final_composite` — `subtitles` filter appended after all overlays (~L590) |
| 2 | Per-segment extract → lossless `-c copy` concat | **CODE** | `extract_all_segments` + `concat_segments` (`-c copy`, ~L281) |
| 3 | 30ms audio fades at every segment boundary | **CODE** | `extract_segment` bakes `afade=in d=0.03 / out d=0.03` (~L201) |
| 4 | Overlays `setpts=PTS-STARTPTS+T/TB` | **CODE** | `build_final_composite` PTS-shift per overlay (~L576) |
| 5 | Master SRT uses output-timeline offsets | **CODE** | `build_master_srt`: `out = word.start - seg_start + seg_offset` (~L376) |
| 6 | Never cut inside a word | **PROSE** | SKILL.md only — an EDL-authoring decision; no code path checks it |
| 7 | Pad every cut edge (30–200ms window) | **PROSE** | SKILL.md only — authoring craft; render.py executes whatever ranges it's given |
| 8 | Word-level verbatim ASR; never SRT/phrase, never normalized fillers | **HYBRID** | CODE: `transcribe.py` requests `verbose_json` word-level + normalizes `type:"word"`. BUT the default **Groq** path *drops* um/uh fillers (docstring + SESSION-HANDOFF) → "verbatim filler removal" requires swapping to `transcribe_elevenlabs.py` (`ELEVENLABS_API_KEY`). Word-level = enforced; *verbatim* = not, on the default path. |
| 9 | Cache transcripts per source | **CODE** | `transcribe_one`: returns existing `transcripts/<stem>.json` if present (~L209) |
| 10 | Parallel sub-agents for multiple animations | **PROSE** | SKILL.md only — a workflow instruction to the model; no code orchestrates it |
| 11 | Strategy confirmation before execution | **PROSE** | SKILL.md only — the ask→confirm gate; nothing in code blocks an unconfirmed run |
| 12 | All session outputs in `<videos_dir>/edit/` | **HYBRID** | CODE *defaults* `edit_dir` to `<video_parent>/edit` (transcribe) and writes relative paths there. BUT `render.py -o` can write anywhere → enforced-by-**default**, not prevented. |

**Punchline (why this file, why Option B):** calling render.py et al. directly (Option A)
would keep **R1–R5 and R9** — they live in the code you'd call — but **silently lose
R6, R7, R10, R11** (and the verbatim half of R8), which live only in SKILL.md prose.
That is the entire reason the director must invoke the *skill*, not its scripts.

## 6. Code-vs-prose divergences the director must build to (CODE WINS)

- **Caption MarginV.** SKILL.md prose says `MarginV=35`. `render.py` ships
  `SUB_FORCE_STYLE` with **`MarginV=80`** (comment: it's a platform safe-zone rule —
  clears the IG/TikTok/Shorts bottom UI band; don't drop below ~75). SESSION-HANDOFF
  says 90. **Use 80** — it's what actually renders. Treat it as a platform rule, not taste.
- **EDL extra fields.** render.py reads `grade:"auto"` and `flashes[]`, which the
  SKILL.md EDL example omits. The read-only reference in §4 includes them.
- **HDR + portrait are handled in code.** `render.py` auto-detects HLG/PQ HDR sources
  and prepends a `zscale+tonemap` chain → Rec.709 SDR, and auto-detects portrait to
  scale-by-height. These are NOT in the 12 rules but ARE in the code path. See §7.

## 7. Two constraints for the Phase-1 authors (PRE/POST must not fight render.py)

`render.py` already bakes in, on every render, behaviors that are **not** in the 12 rules
and **not** the director's job to redo. If `prep.sh` / `package.sh` repeat them, output is
double-processed:

1. **Loudness.** render.py runs **two-pass loudnorm to −14 LUFS / −1 dBTP / LRA 11** by
   default (`apply_loudnorm_two_pass`; `--no-loudnorm` to skip). So `final.mp4` is already
   social-loudness-correct. `package.sh` should **not** loudnorm again unless it first
   `--no-loudnorm`'d upstream; at most verify, don't re-normalize.
2. **HDR→SDR tonemap + scale-to-1080p.** render.py tonemaps HDR and scales to 1920 (long
   edge) per segment. PRE `prep.sh` reframe/stabilize should hand video-use a clean SDR
   source where possible and **not** pre-tonemap in a way that conflicts; POST `package.sh`
   re-encodes for platform aspect/codec/bitrate but should treat `final.mp4` as already
   graded/normalized/tonemapped — it is a container/aspect/codec step, not a grade step.
3. **Grade presets live in `grade.py`** (`warm_cinematic`, `neutral_punch`, `none`). The
   director routes a *grade direction* into the EDL `grade` field via the baton; it does
   not apply grades itself.

---

### File written
`~/.claude/skills/video-director/references/baton-handoff.md`

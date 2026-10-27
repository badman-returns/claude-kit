# Video Director — Multi-Agent Build Strategy

> How to build the skill (per SPEC.md v2) with parallel agents. Sized per the
> review: the value is in the **bookends** (contract up front, coherence pass at
> the end), not in fan-out width. 3 parallel authors is the ceiling here.

## Shape: discovery → fan-out(3) → integrate

```
 PHASE 0 (1 agent, sequential)          PHASE 1 (3 agents, parallel)        PHASE 2 (1 agent, sequential)
 ┌──────────────────────────┐          ┌──────────────────────────┐        ┌──────────────────────────┐
 │ CONTRACT DISCOVERY        │          │ A · Environment           │        │ INTEGRATION + COHERENCE   │
 │ map video-use baton       │  ───►    │ B · PRE/POST + recipes    │  ───►  │ wire seams · run doctor   │
 │ boundary → handoff.md     │  (gate)  │ C · SKILL.md (workflow)   │ (gate) │ · dry-run on sample clip  │
 └──────────────────────────┘          └──────────────────────────┘        └──────────────────────────┘
        BLOCKS everything         each writes DISJOINT files (no conflict)      budget real effort here
```

**Why a hard gate after Phase 0:** all three authors build against the baton
contract (`handoff.md` — what video-use reads, where it writes, code-vs-prose rules).
Fan out before it's pinned and you get three incompatible guesses.

**Why no worktree isolation:** the three authors write to *disjoint files* in the
same skill dir (A→scripts/{doctor,install,probe}; B→scripts/{prep,package}+references/;
C→SKILL.md). No file collisions, so no worktree overhead needed.

## Phase 0 — Contract discovery (1 agent)
- Read `~/.claude/skills/video-use/` fully: `SKILL.md`, `helpers/render.py`,
  `grade.py`, `transcribe*.py`, session-memory files.
- Produce `references/handoff.md`: invocation trigger, the context fields video-use
  accepts at start (to skip re-asking intake), output location, `edl.json` shape
  (read-only), and **a table of the 12 correctness rules tagged code vs prose**.
- **Gate:** human/lead confirms the baton boundary before fan-out.

## Phase 1 — Three parallel authors

**A · Environment** → `doctor.sh`, `install.sh`, `probe.sh`
- `install.sh`: provision `~/.video-director-venv` (Python 3.11), install
  `backgroundremover` there; register obs-mcp at user scope; idempotent, confirm-each.
- `doctor.sh`: readiness table incl. venv health + the ffmpeg-filter check.
- `probe.sh`: ffprobe → normalized JSON (res, fps, aspect, dur, audio, loudness).

**B · PRE/POST + recipes** → `prep.sh`, `package.sh`, `pipelines.md`, `platform-presets.md`
- `prep.sh`: PRE source-prep — safe-crop reframe, vidstab stabilize, bg-removal
  (calls venv). Only the ⚙/venv steps; mark ⚠ rows as unbuilt.
- `package.sh`: POST platform-correct encode (aspect/codec/bitrate/loudnorm) reading presets.
- recipes: every matrix row → a real command or an explicit ⚠ flag (no vapor).

**C · SKILL.md** → the conversational spine
- Frontmatter (incl. `allowed-tools` for ffmpeg/obs MCP, `${CLAUDE_SKILL_DIR}` refs).
- PRE workflow (intake interview, probe, route, prep) → **baton pass** (invoke
  video-use + write handoff file) → POST (package, variations).
- Stage-gate rules: confirm each step; never advance without approval; show proof.
- Builds against `handoff.md` — does NOT re-implement edl.json or the 12 rules.

## Phase 2 — Integration + coherence (1 agent, sequential — budget real effort)
- Resolve seams: does C's baton call match A's installed tools and B's script names/flags?
- Run `doctor.sh`; if anything red, fix or document.
- **Dry-run on a real sample clip** through PRE → (mock or real baton) → package.
- Output a short "what works / what's stubbed (⚠) / open questions" report.

## Execution
- This is explicit multi-agent work → run as a **Workflow** (1 → parallel 3 → 1).
- **prompt-architect: skipped** — the validation + `handoff.md` give richer grounding
  than a generic repo scan; spawn prompts authored directly from SPEC.md v2.
- Estimated: Phase 0 ~1 agent, Phase 1 ~3 concurrent, Phase 2 ~1. Small, tight, ~5 files.

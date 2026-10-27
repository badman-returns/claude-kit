# Preview & Editor Handoff

> Two ways to see/work the cut: a built-in **viewer** for quick review, and an
> export to a real **NLE** (DaVinci Resolve) for hands-on timeline editing.
> Neither is custom-built — the viewer ships with video-use; the handoff uses
> the industry-standard OpenTimelineIO.

## Layer 1 — Built-in timeline viewer (ALREADY EXISTS, zero build)

`video-use` ships `helpers/preview_server.py`. It reads `edl.json`, generates
`timeline.html`, and serves it on localhost:
```bash
python helpers/preview_server.py "<edit_dir>" --port 8777      # serve at localhost:8777
python helpers/preview_server.py "<edit_dir>" --no-serve       # just write timeline.html
```
**Shows:** the rendered video playing + a clickable timeline of every take segment,
the motion-graphics overlay windows marked on top, and a live playhead. Click a
segment → jump to it. Scrub the whole cut.

**It is a VIEWER, not an EDITOR** — you can see/scrub the cut, not drag/trim/reorder
clips. For that, use Layer 2. (Optional richer browser view: OTIO's **Raven** web viewer.)

## Layer 2 — Hand off to a real editor (DaVinci Resolve) via OpenTimelineIO

The user already runs DaVinci (see their `DaVinci Output/` folder). To open the AI's
cut as a real multi-track timeline they can drag/trim/tweak:

```
edl.json  →  OTIO  →  FCPXML / EDL (CMX3600)  →  import in DaVinci Resolve
```

- **OpenTimelineIO (OTIO)** — Academy Software Foundation interchange standard
  (originated at Pixar). Has official adapters to **FCPXML** and **EDL**; DaVinci,
  Premiere, and FCP all import those.
- Only glue needed: a tiny `edl.json → OTIO → FCPXML` exporter. OTIO does the heavy
  lifting (`pip install opentimelineio` in the py3.11 venv).
- Result: all 14 segments land in DaVinci as a real timeline; user edits normally,
  then renders from DaVinci (or round-trips back).

## POST-phase deliverable

Add an **"Open in editor"** option to the director's POST phase:
- `package.sh` (or a new `handoff.sh`) emits `edit.fcpxml` next to `final.mp4`.
- The director offers it after render: *"Want the scrub-preview (localhost:8777), or
  the DaVinci timeline (edit.fcpxml) to tweak by hand?"*

## Browser-editor alternatives (only if NLE handoff is ever not enough)

Maintained open-source options — likely overkill given DaVinci is already in use:
- **Twick** — open-source React SDK for AI-powered timeline editors (drag/trim/layer).
- **Remotion Player + Timeline** — interactive preview (timeline component is paid).
- **react-video-editor** — basic open-source browser editor.

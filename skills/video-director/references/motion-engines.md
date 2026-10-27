# Motion / Overlay Engines — selector

> The director (and video-use) can render overlay/animation slots with **several
> engines**, not just HyperFrames. They are interchangeable because of one contract.

## The contract that makes engines swappable

Every overlay in `edl.json` is just a pointer to a rendered clip:
```json
{ "file": ".../slot_N/render.mp4", "start_in_output": 25.65, "duration": 12.0, "beat": "THE_BUG" }
```
The slot does not care *how* `render.mp4` was made. **Any engine that renders a clip
at the right dimensions slots in** — full-frame, or with alpha (ProRes 4444 / WebM
VP9-alpha / PNG sequence) for overlays that sit on top of footage. Adding an engine =
teaching the director one more "concept → render.mp4" recipe.

## Engine catalog

| Engine | Tech | Looks like | Best for | In video-use today |
|--------|------|-----------|----------|:---:|
| **HyperFrames** | HTML/CSS/GSAP | Web/app UI, smooth | UI & data-flow diagrams, **brand-matched** (CSS = exact blog tokens), kinetic type | ✅ |
| **Remotion** | React | Web, data-driven | Charts, **templated variations**, hosts Lottie, complex comps | ✅ |
| **Manim** | Python | Mathematical, precise | Math, algorithms, geometric step-reveals (3Blue1Brown look) | ✅ (vendored) |
| **PIL → ffmpeg** | Python imaging | Simple cards | Fast lower-thirds, text, lowest dependency | ✅ |
| **Motion Canvas / Revideo** | TypeScript | Code-timeline | Precise technical animation, timeline control | ➕ add |
| **Lottie** | After Effects JSON | Designer-polished | Playing back designer-made animations | ➕ via Remotion |
| **Blender** | 3D | Cinematic 3D / VFX | 3D objects, product shots, heavy effects | ➕ add (heavy) |

## Selector — by what the overlay must SHOW

| Overlay shows… | Engine |
|---|---|
| A flow / how data moves through a system | **HyperFrames** (CSS, brand-matched) |
| Math, an algorithm, a graph being drawn | **Manim** |
| Numbers / charts / live data viz | **Remotion** |
| Same card in N variations (personalized) | **Remotion / Revideo** |
| A designer's pre-made animation (.json) | **Lottie** in Remotion |
| A rotating 3D product / object | **Blender** |
| Quick text card / lower-third, fast | **PIL** or HyperFrames |

**Taste layer:** brand-matched-to-website → HyperFrames/Remotion (CSS uses exact hex);
chalkboard-explainer → Manim; filmic 3D → Blender.

## Giving the user variation

1. **Bake-off** — render a hero slot in 2 engines (e.g. HyperFrames vs Manim), show
   both, user picks. More compute, best for key moments.
2. **Style knob** — "make this one more mathematical" re-routes that single slot to
   Manim; the rest stay.

## Install priority (for the build)

1. **HyperFrames, Remotion, Manim, PIL** — already wired, zero work.
2. **Lottie-via-Remotion** — add first; unlocks any designer asset with no new runtime.
3. **Motion Canvas / Revideo** — add if precise code-timeline control is wanted.
4. **Blender** — last; heavy, niche (only when true 3D is needed).

## Real example (IMG_3091)

The 3 diagrams (THE READ PATH / THE BUG / THE FIX) were UI data-flow, brand-matched
to the blog palette → **HyperFrames was correct.** The same "THE BUG" beat could have
been **Manim** (abstract/mathematical) or **Remotion** (if driven by real row-count data).

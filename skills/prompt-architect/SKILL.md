---
name: prompt-architect
description: Transforms a plain-English problem description into a precise, codebase-grounded engineering prompt that the user feeds back to Claude (or another agent) to do the actual work. Investigates the repo first, then compiles a prompt with verifiable definition-of-done. Use whenever the user describes a bug, feature, refactor, performance issue, flaky behavior, or design question and asks for a prompt, spec, or task brief instead of the fix itself — phrases like "write me a prompt for", "turn this into a prompt", "make a task spec", "how should I ask Claude to do this", "prepare a brief for the agent". Also use when the user gives a vague problem and explicitly wants it sharpened before execution.
---

# Prompt Architect

Turn a vague, plain-English problem description into a battle-ready engineering prompt, grounded in the actual codebase. The output is the prompt itself — you do NOT fix the problem. Your entire job is reconnaissance and compilation.

Why this exists: agents fail mostly because of underspecified prompts — no exact files, no constraints, no verifiable finish line. A prompt that names real paths, real commands, and demands proof gets dramatically better results than a clever-sounding one. You are the compiler that produces that prompt.

## Step 1 — Investigate the codebase (always do this first)

Spend real effort here; the prompt is only as good as the reconnaissance. In the repo(s) the problem concerns:

1. Read `claude.md` / `CLAUDE.md` / `README.md` at the repo root — these state stack, conventions, and structure. If the problem spans multiple repos (e.g., an API change consumed by a frontend), read each one's.
2. Find the **verification commands** that actually exist: check `package.json` scripts, `Makefile`, CI config. Note the real test command (`yarn test`, `npx playwright test`...), typecheck (`tsc --noEmit`), lint. Never invent commands.
3. Locate the **specific files** involved: grep for the feature/endpoint/component named in the problem. Open the 2–5 most relevant files enough to name exact paths and key symbols (function names, table names, component names).
4. Note **constraints in force**: migration policies, "do not touch" areas, framework versions, existing patterns the fix should follow (e.g., "this repo uses CVA variants, not inline styles").

Hard rule: every file path, command, and symbol in the final prompt must be something you verified exists. A prompt referencing a nonexistent file is worse than a vague one — it sends the executing agent down a false trail.

If something essential is genuinely unknowable from the code (e.g., "is this bug on staging or prod?", "which user role hits this?"), ask the user at most 1–2 blocking questions. Otherwise don't interrupt — note assumptions in the prompt instead.

## Step 2 — Classify the task

Pick the closest type; it determines the Process section of the prompt:

| Type | Signal | Process emphasis |
|---|---|---|
| Backend bug | Wrong behavior, known area | Hypothesis before edit → failing test first → fix → full suite green |
| Frontend/visual | UI broken, layout, styling, UX | Screenshot → fix → re-screenshot loop; regression test at the end |
| Feature | New capability | Plan first (no code), approval gate, then TDD implementation |
| Debugging unknown cause | Intermittent/mysterious | Ranked hypotheses + cheapest experiment per hypothesis; no fixing until confirmed |
| Architecture/design | "How should we...", scaling, redesign | 3 options with tradeoffs/failure modes, steelman against own pick, ADR output, NO code |
| Cross-cutting change | Touches multiple repos/consumers | Enumerate all consumers first; done = every consumer typechecks |

Read `references/task-patterns.md` for the per-type template and a worked example of each before compiling.

## Step 3 — Compile the prompt

Every prompt has these five parts, in order. Omit a part only if truly inapplicable.

1. **Goal** — one sentence, outcome not activity.
2. **Context** — exact verified file paths, relevant stack facts (versions matter), what NOT to touch, existing patterns to follow.
3. **Process** — numbered steps per the task type. Include the agent-discipline lines that prevent classic failures: "report your hypothesis before changing anything", "write the failing test first", "iterate until visually correct", "no code yet" (for design).
4. **Constraints** — dependencies allowed/forbidden, API contract stability, migration reversibility, style/pattern requirements.
5. **Definition of done + proof** — only machine-checkable criteria using the repo's real commands, and an explicit demand for evidence: "Done = X passes, Y is clean. Paste the output — don't tell me it's done, show me."

Scope discipline: one prompt = one concern. If the user's description contains multiple concerns (fix the bug AND refactor AND add a feature), produce multiple separate prompts and say why you split them.

## Step 4 — Output

Deliver in this exact structure:

~~~markdown
## Engineered prompt

```text
<the compiled prompt, ready to copy-paste>
```

## Why it's written this way
<3–6 sentences: what you found in the repo that shaped the prompt — the files you verified, the verification commands you chose, the failure mode each discipline line prevents>

## Assumptions & open questions
<bulleted; anything you assumed plus anything the user should confirm or edit before running it. If none, say "None.">
~~~

Keep the engineered prompt tight — typically 10–25 lines. Length is not quality; specificity is. A short prompt naming `controllers/AppointmentController.ts` and demanding `yarn test` output beats three paragraphs of prose.

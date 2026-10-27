# Task-type patterns

Per-type process templates with worked examples. The examples use an online booking platform (Express+Knex backend "booking-api", React SPA "booking-web") — adapt structure, not specifics, to the repo at hand.

## Backend bug (known area, wrong behavior)

Process skeleton:
1. Read <verified files>. Identify the cause. **Report your hypothesis before changing anything.**
2. Write a failing test that reproduces the bug. It must fail on current code.
3. Fix. Prefer the strongest guarantee available (DB constraint > transaction > app-level check). Justify the choice in one paragraph.

Constraints to consider: no new dependencies, API contract unchanged, migrations reversible.
Done: new test passes + full suite green + typecheck clean. Paste output.

Why hypothesis-before-edit: it stops shotgun fixes. Why failing-test-first: it proves the bug exists and proves the fix fixed it.

Worked example:

```text
In booking-api, customers can double-book a slot when two requests hit
POST /appointments concurrently.

1. Read controllers/AppointmentController.ts and the slots migration.
   Identify where the check-then-insert race lives. Report your
   hypothesis BEFORE changing anything.
2. Write a failing Jest test simulating two concurrent bookings for the
   same slot (Promise.all). It must fail on current code.
3. Fix it — prefer a DB-level guarantee (unique partial index or pg
   advisory lock inside a Knex transaction). Justify your choice.

Constraints: no new deps, API contract unchanged, migration reversible.
Done = new test passes, `yarn test` green, `tsc --noEmit` clean.
Paste the test output.
```

## Frontend / visual

Process skeleton:
1. Run the dev server; capture "before" evidence (screenshots at the relevant viewports, or browser console/network logs). Describe what's wrong in your own words.
2. Fix using the repo's existing styling patterns (name them — e.g., "Tailwind + CVA variants like <verified component> uses"). Forbid the shortcuts that cause drift (inline styles, new CSS files) if the repo avoids them.
3. Re-capture and compare against before. **Iterate until visually correct.**
4. Add a regression test (Playwright/e2e if the repo has it) so it can't silently return.

Done: e2e green + before/after screenshots saved. If the repo has Playwright configured, always use it — agents are far better at frontend when they can see their work.

Worked example:

```text
In booking-web, pages/Staff/Schedule/ overflows horizontally under 380px.

1. Run dev server; Playwright-screenshot the page at 375x667 and
   320x568. Describe what's broken.
2. Fix with existing Tailwind patterns (see how Session.tsx handles
   narrow viewports; we run in a WebView — read SAFE_AREA_GUIDE.md).
   No new CSS files, no inline styles.
3. Re-screenshot both viewports, compare to before. Iterate until right.
4. Add an e2e in e2e/ asserting no horizontal overflow at 320px.

Done = e2e suite green, before/after screenshots in screenshots/.
```

## Feature (new capability)

Two-phase — and say so explicitly in the prompt:
- Phase 1: plan only. List files to create/modify, data model changes, API surface, edge cases, test plan. **No code. Stop for approval.**
- Phase 2 (after approval): implement test-first, smallest reviewable increments.

This split exists because bad plans are cheap to fix and bad implementations aren't. Include in context: the nearest existing feature to mimic ("follow the same controller/service/migration structure as <verified feature>").

## Debugging unknown cause (intermittent / mysterious)

Process skeleton:
1. **Do NOT fix anything yet.**
2. Rank your top 3 hypotheses by likelihood. Seed candidates from the recon (e.g., React StrictMode double-fire, retry logic in the HTTP client, env-shared cache keys).
3. For each: the cheapest experiment that would confirm or kill it.
4. Run the experiments that are runnable locally. Only then propose the fix.

Why: forcing ranked hypotheses + cheap experiments prevents the classic agent failure — confidently fixing the wrong thing.

## Architecture / design

Process skeleton:
1. Required reading first: the design docs and code areas you verified (name them).
2. Produce exactly 3 options. For each: complexity, failure modes ("what happens if <dependency> dies mid-operation?"), migration path from current state, operational cost for the actual team size.
3. Recommend one. **Steelman the strongest argument AGAINST your recommendation.**
4. Output an ADR to the repo's docs location. **No code yet.**

The steelman line is the difference between an agent that flatters and one that thinks. "No code yet" keeps design quality high by separating it from implementation.

## Cross-cutting change (multiple repos / many consumers)

Process skeleton:
1. Before changing anything, grep every consuming repo for usages of the contract being changed (endpoint, response shape, shared type). List them all.
2. Make the change, updating every consumer.
3. Done = every affected repo typechecks and its tests pass — list the commands per repo (verified from each repo's package.json).

If the change can be staged (additive field first, remove later), the prompt should require the agent to propose the staged path.

## Universal discipline lines (use wherever they fit)

- "Report your hypothesis before changing anything."
- "Write the failing test first — it must fail on current code."
- "Don't tell me it's done — paste the passing output."
- "No code yet." (design/planning phases)
- "Steelman the strongest argument against your recommendation."
- "Iterate until the screenshots match the requirement."
- One prompt = one concern; split anything bigger.

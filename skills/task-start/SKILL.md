---
name: task-start
description: "Git branch setup for new tasks: pull main (production), rebase development on it with intelligent conflict resolution, create a new task branch. Run before every implementation task."
trigger: /task-start
---

# /task-start

Prepares the git environment before any implementation task by syncing branches and creating a clean task branch. Includes a full conflict resolution protocol when the rebase fails.

**Branch model:**
- `main` — production (source of truth, targeted hotfixes land here)
- `development` — integration branch (features accumulate here, ahead of production)
- `PROJ-1234/description` or `description` — per-task branch (created here)

Rename `main` and `development` in the commands below if your repository uses other names.

---

## What You Must Do When Invoked

Follow these steps in order. Do not skip any step.

### Step 1 — Check for uncommitted work

```bash
git status --short
```

If there are uncommitted changes or untracked files, stop and tell the user:
> "You have uncommitted changes. Please commit, stash (`git stash`), or discard them before running /task-start."

Do not proceed until the working tree is clean.

### Step 2 — Pull latest main (production)

```bash
git fetch origin
git checkout main
git pull origin main
```

If checkout or pull fails, report the error and stop.

### Step 3 — Update development and rebase on main

```bash
git checkout development
git pull origin development
git rebase main
```

**If the rebase succeeds:** print a one-line confirmation and jump to Step 4.

**If the rebase fails with conflicts:** immediately enter the **Conflict Resolution Protocol** below. Do not stop and ask the user to resolve conflicts manually — work through them intelligently first.

---

## Conflict Resolution Protocol

This protocol runs whenever `git rebase main` exits with conflicts. Work through it completely before continuing to Step 4.

### Phase 1 — Triage: understand the battlefield

Run all of these commands to build a full picture before touching a single file.

```bash
# 1. List every conflicted file
git diff --name-only --diff-filter=U

# 2. Classify production-side changes (what hotfixes landed in main that are NOT in development)
git log --oneline --format="%H %ci %s" main --not development -- $(git diff --name-only --diff-filter=U | tr '\n' ' ') 2>/dev/null | head -20

# 3. Show recent development commits on those same files (to understand what features touch them)
git log --oneline --format="%H %ci %s" development --not main -- $(git diff --name-only --diff-filter=U | tr '\n' ' ') 2>/dev/null | head -20

# 4. For each conflicted file, see which commit in main last touched it
for f in $(git diff --name-only --diff-filter=U); do
  echo "=== $f ==="
  echo "  main last: $(git log --oneline -1 main -- "$f" 2>/dev/null)"
  echo "  development last: $(git log --oneline -1 development -- "$f" 2>/dev/null)"
done
```

Use this output to build a mental map of each conflict before resolving anything.

### Phase 2 — Classify each conflict

For every conflicted file, determine its **change type** and **conflict category** using the rules below.

#### 2A — Classify the production (main) change

Read the commit message that last touched this file in main. Apply the first matching rule:

| Pattern in commit message | Classification |
|---|---|
| Contains `-fix`, `fix:`, `hotfix`, `patch`, `revert`, `security` | **HOTFIX** — targeted repair, must be preserved |
| Contains a ticket key such as `PROJ-1234` only (no fix/feat qualifier) | **FEATURE-PROD** — a feature that was merged to prod; treat same as hotfix for conflict purposes |
| Contains `sprint-*` branch merge | **SPRINT-MERGE** — batch of features; check individual commits inside it |
| Contains `Merge pull request` only | **MERGE-COMMIT** — skip, look at the underlying commit instead |
| No match | **UNKNOWN** — flag for manual review |

#### 2B — Classify the development change

Read the commit message that last touched this file in development. Apply the first matching rule:

| Pattern in commit message | Classification |
|---|---|
| Contains `feat:`, `PROJ-1234: ` with descriptive suffix | **FEATURE-DEV** — new functionality being added |
| Contains `fix:` | **FIX-DEV** — a bug fix on the development branch |
| Contains `refactor:`, `chore:`, `style:` | **CLEANUP-DEV** — non-functional change |
| No match | **UNKNOWN** — flag for manual review |

#### 2C — Classify the file type

| File pattern | File type |
|---|---|
| `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` | **DEPS** |
| `*.config.ts`, `*.config.js`, `vite.config.*`, `jest.config.*`, `tsconfig*.json` | **CONFIG** |
| `*.env`, `.env.*`, `*.env.*` | **ENV** |
| Path contains `/__tests__/`, `/test/`, `/spec/` or filename contains `.test.`, `.spec.` | **TEST** |
| `*.tsx`, `*.ts`, `*.jsx`, `*.js` (component or service) | **CODE** |
| `*.scss`, `*.css`, `*.module.css` | **STYLE** |
| Any other file | **OTHER** |

### Phase 3 — Apply the resolution strategy

For each conflicted file, apply the first matching rule in this decision matrix:

#### Rule 1 — DEPS file
```bash
# Do NOT use checkout --ours or --theirs on package.json.
# Read both conflict blocks manually and construct the merged result.
```
- For `dependencies` / `devDependencies`: take the **union** of all packages from both sides. Where the same package has two different versions, take the **higher version**.
- For `scripts`, `engines`, `browserslist`: take development's values (they reflect the current build setup).
- For `version` field: take development's value.
- After editing, run `git add <file>`.

#### Rule 2 — ENV or CONFIG file + HOTFIX production change
```bash
git show HEAD:<file>  # read the main version
git show MERGE_HEAD:<file> 2>/dev/null || git show ORIG_HEAD:<file>  # read the development version
```
- Keep ALL keys/values from main (production config is trusted for correctness).
- Add any NEW keys that exist only in development (feature flags, new service URLs).
- If the same key has conflicting values: take main's value and add a comment `// TODO: verify this value for feature <ticket>`.
- After editing, run `git add <file>`.

#### Rule 3 — TEST file
```bash
git checkout --theirs <file>  # development's tests are for development's features
git add <file>
```

#### Rule 4 — STYLE file
Read both conflict blocks. Take development's version as the base, then manually add any production-side style rules that are not present in development. Style conflicts are almost always additive.
```bash
git add <file>
```

#### Rule 5 — CODE file + HOTFIX production change + conflict block ≤ 15 lines

This is the most common and most important case: a small targeted bug fix in production conflicting with feature code in development.

**Strategy: keep development's structure, surgically apply the production fix.**

Steps:
1. Read the full conflicted file — identify every `<<<<<<<`, `=======`, `>>>>>>>` block.
2. For each conflict block:
   a. Read the `<<<<<<< HEAD` section (main / production).
   b. Read the `>>>>>>> <hash>` section (development commit being applied).
   c. Determine what the production change actually *fixed* (a null check? a missing return? a wrong variable name?).
   d. Take the **development side** as the base.
   e. Apply the production fix *within* the development code. This usually means adding a guard condition, correcting a variable name, or fixing a return value — not swapping entire blocks.
3. Write the resolved file (no conflict markers remaining).
4. Run `git add <file>`.

**Example pattern:**
```
<<<<<<< HEAD (main)
const value = data?.items ?? [];   // hotfix added null-safety
=======
const value = data.items;          // development's version (old, pre-fix)
>>>>>>> abc123 (development commit)
```
→ Correct resolution: `const value = data?.items ?? [];` (take the fix, it's strictly better)

#### Rule 6 — CODE file + FEATURE-PROD production change + conflict block ≤ 30 lines

Both sides added features. They need to coexist.

Steps:
1. Read both conflict sections carefully.
2. Identify what each side *added* (new imports, new props, new logic branches).
3. Construct a merged version that includes both additions without duplication.
4. If a function signature changed on the main side and development is calling the old signature, update the call sites in the development code.
5. Write the resolved file and run `git add <file>`.

#### Rule 7 — CODE file + conflict block > 30 lines

Large conflicts require human judgment. Do the following:
1. Accept development's version as the working base: `git checkout --theirs <file>`
2. Run `git add <file>`
3. **Immediately create a TODO comment** at the top of the conflict area:
   ```typescript
   // REBASE-TODO: main had significant changes here that were not auto-merged.
   // Review: git show <main-commit-hash>:<file>
   // Compare with this development version and manually apply any hotfixes.
   ```
4. Log this file in the summary report (Phase 5).

#### Rule 8 — UNKNOWN classification on either side

Do not guess. Take development's version, add a REBASE-TODO comment, and log it.

### Phase 4 — Continue the rebase

After all conflicted files are resolved and staged:

```bash
git rebase --continue
```

If this triggers another conflict (rebase is multi-step), return to Phase 2 and repeat for the new conflict set. The rebase may go through several rounds if development has many commits.

If `git rebase --continue` exits cleanly: proceed to Phase 5.

### Phase 5 — Post-resolution report

Print a structured summary after the rebase completes:

```
Rebase complete. Conflict resolution summary:
──────────────────────────────────────────────
Auto-resolved:
  <file>  [HOTFIX + CODE → merged production fix into development code]
  <file>  [DEPS → merged dependency sets, took higher versions]
  <file>  [TEST → accepted development tests]
  ...

Needs manual review (REBASE-TODOs added):
  <file>  [reason: large conflict block, production change not applied]
  ...

Production fixes applied:
  <brief description of each hotfix that was incorporated>

Next: run `git diff HEAD development` to verify the full diff looks correct.
     Then: continue to branch creation.
```

If there are REBASE-TODO files, explicitly tell the user which files need attention before the task branch is safe to use.

---

### Step 4 — Ask for task details

Ask the user two questions in a single message:
1. "What is the ticket key? (e.g. `PROJ-3200`, leave blank if none)"
2. "Short task description? (e.g. `fix-login-button-alignment`)"

Construct the branch name:
- With ticket: `<ticket-key>/<kebab-case-description>`
- Without ticket: `<kebab-case-description>`

Rules: lowercase, hyphens for spaces, strip special characters, max 50 chars on the description part.

Show the proposed branch name and confirm before creating it.

### Step 5 — Create the task branch

```bash
git checkout -b <branch-name>
```

Confirm with:
```
Branch created: <branch-name>
Base: development (rebased on main)
Ready to work.
```

If the branch name already exists, append `-2` and inform the user.

---

## Full flow summary

```
main (pull)
    │
    ▼
development (pull → rebase on main)
    │  conflicts? → triage → classify → resolve per rule → continue
    ▼
<task-branch> (new, clean, up-to-date)
```

Every task branch starts from a development baseline that is fully rebased on production, with all hotfixes incorporated.

---
name: browser
description: "Drive a real Chrome browser to do a task on a website — open a link the user shares, then click, type, fill forms, read content, and automate a flow. Optionally with a visible animated cursor (demo mode). Use whenever the user shares a URL and asks to do something on it, says 'use the browser', 'open this in the browser', 'log in and…', 'fill this form', 'go to this site and…', or wants to watch the browser being driven."
trigger: /browser
---

# /browser

Open and drive the user's local debug Chrome (chrome-devtools-mcp over CDP on
:9222) to accomplish a web task. Default to **fast** (direct, no overlay); switch
to **demo** (animated cursor glide + per-key typing) only when the user wants to
watch.

Backing setup lives in `~/cdp-browser-automation/` (see its `SETUP.md`). This
skill is the entry point: it brings the browser up, picks a mode, gets the link,
and does the work.

## Usage
```
/browser                         # bring browser up (fast), then ask what to do / for a link
/browser <url> <instructions>    # open url and do the instructions
/browser demo <url> ...          # same, but with the visible animated cursor
/browser watch ...               # alias for demo
/browser fast ...                # force fast mode (default)
```

> Note: this drives **local** Chrome on this machine, so it runs wherever this
> machine's Claude Code runs — it is global across your projects but is **not** a
> remote/cloud sandbox. The browser window opens on this Mac.

## How to run this skill

### 1. Bring the browser up (always first)
Pick the mode from the user's words: **demo** if they say demo / watch / show me /
animate / glide; otherwise **fast**.
```bash
~/cdp-browser-automation/browser-up.sh demo   # or: fast
```
This launches the debug Chrome if it isn't already on :9222 (idempotent — returns
instantly if already up) and starts/stops the demo companion accordingly.

### 2. Get the link
If the user gave a URL, use it. If not, ask them to share the link (and any
specifics: what to do, what counts as done). Don't guess destinations.

### 3. Drive the browser

**Reuse the tab the user already has open** when the task is about a page that's
already loaded — don't blindly open a new tab. Check first:
- fast → `mcp__chrome-devtools__list_pages`, then `select_page` the matching one.
- demo → `./bctl.mjs pages`, then `./bctl.mjs use --url "<substring>"`.
Only `navigate_page` / `goto` to a fresh URL if the right tab isn't already open.

**FAST mode → use the `chrome-devtools-mcp` tools directly** (the fast, low
round-trip path):
- `mcp__chrome-devtools__navigate_page` — go to the URL.
- `mcp__chrome-devtools__take_snapshot` — get the accessibility tree + element
  uids. Prefer this over screenshots for reading/locating.
- `mcp__chrome-devtools__click` / `fill` / `fill_form` / `type_text` — act.
  Prefer `fill_form` to batch several fields in one call.
- `mcp__chrome-devtools__evaluate_script` — read or set values directly instead
  of clicking through the UI when reliable.
- `mcp__chrome-devtools__wait_for` — wait on element/state, not fixed sleeps.

**DEMO mode → route input through the companion so it's visible** (`bctl.mjs`):
```bash
cd ~/cdp-browser-automation
./bctl.mjs goto  --url "<URL>"
./bctl.mjs click --selector "<css>"            # or --x N --y N
./bctl.mjs type  --selector "<css>" --text "…" --submit Enter
./bctl.mjs move  --selector "<css>"            # glide only
./bctl.mjs pages                               # list tabs
```
You can still use `mcp__chrome-devtools__take_snapshot` / `evaluate_script` to
READ the page in demo mode — only the visible *input* goes through `bctl`.

### 4. Report
Say what you did and the outcome (and paste any result the user asked for). Take a
screenshot only if it adds something the text can't convey.

## Speed rules (fast mode default)
- Snapshots/scoped `evaluate_script` reads over full-page screenshots; don't
  screenshot every step.
- Navigate directly (`navigate_page` to a URL) and read/set via `evaluate_script`
  instead of clicking element-by-element. Batch form fields with `fill_form`.
- State-based waits (`wait_for`), never fixed sleeps. Do **not** wait on
  `networkidle` for SPA-heavy sites (Google Docs, Gmail, etc.).

## Logins & safety
- The debug profile persists sessions. If a site needs a login the user hasn't
  done in this profile, pause and ask them to log in once in the debug Chrome
  window (`~/cdp-browser-automation/chrome-debug.sh` opens it); the session sticks
  after that.
- Before any **outward-facing or hard-to-undo action** (sending/posting,
  submitting payments, deleting, messaging people, irreversible account changes),
  confirm with the user first unless they've clearly authorized it for this task.

## Troubleshooting
- `browser-up.sh` says it failed → Chrome may be open on the *default* profile
  (remote debugging is blocked there on Chrome 136+). Close it or launch the
  separate debug profile via `chrome-debug.sh`.
- `bctl` can't reach the daemon → it's not running; `./browser-mode.sh demo`.
- Switch modes anytime: `./browser-mode.sh demo|fast|stop|status`.

#!/usr/bin/env bash
# Set up any Claude Code config dir with the shared skills + plugins.
#
#   ./bootstrap.sh                 # targets $CLAUDE_CONFIG_DIR or ~/.claude
#   ./bootstrap.sh ~/.claude-work  # targets a specific config dir
#
# Safe to re-run. Requires node on PATH.
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"

echo "Bootstrapping $CONFIG from $KIT"
mkdir -p "$CONFIG/skills"

for src in "$KIT"/skills/*/; do
  name="$(basename "$src")"
  dest="$CONFIG/skills/$name"
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ]; then
    echo "  skip $name (real directory already exists — remove it to adopt the kit copy)"
    continue
  fi
  ln -s "${src%/}" "$dest"
  echo "  linked skill: $name"
done

if [ -f "$CONFIG/settings.json" ]; then
  cp "$CONFIG/settings.json" "$CONFIG/settings.json.bak"
fi
node "$KIT/merge-settings.js" "$KIT/settings-fragment.json" "$CONFIG/settings.json"

echo "Done. Restart Claude Code — declared plugins install automatically on startup."

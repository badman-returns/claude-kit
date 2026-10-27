#!/usr/bin/env node
// Merge a settings fragment into a Claude Code settings.json.
// Object values (extraKnownMarketplaces, enabledPlugins, ...) are merged
// key-by-key with the fragment winning; existing scalar settings are kept.
const fs = require('fs');

const [fragPath, targetPath] = process.argv.slice(2);
if (!fragPath || !targetPath) {
  console.error('usage: merge-settings.js <fragment.json> <settings.json>');
  process.exit(1);
}

const frag = JSON.parse(fs.readFileSync(fragPath, 'utf8'));
let target = {};
try {
  target = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
} catch {
  // no existing settings file — start fresh
}

for (const [key, val] of Object.entries(frag)) {
  if (val && typeof val === 'object' && !Array.isArray(val)) {
    target[key] = { ...(target[key] || {}), ...val };
  } else if (!(key in target)) {
    target[key] = val;
  }
}

fs.writeFileSync(targetPath, JSON.stringify(target, null, 2) + '\n');
console.log('merged ' + fragPath + ' -> ' + targetPath);

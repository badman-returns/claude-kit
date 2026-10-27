# claude-kit

A portable Claude Code toolkit. One repository gives every Claude Code
instance the same custom skills and plugins: any account, any project, any
machine.

I use more than one Claude Code account, and each account has its own config
directory (`CLAUDE_CONFIG_DIR`). Without this kit, every directory drifts: a
skill that I fix in one place stays broken in the others. `bootstrap.sh`
symlinks the skills from this clone into a config directory and merges the
plugin list into its `settings.json`, so a `git pull` updates every instance.

## What is inside

- `skills/`: custom skills. `bootstrap.sh` symlinks each one into the
  `skills/` folder of a config directory.
  - `task-start` (`/task-start`): git branch setup before implementation. It
    pulls the production branch, rebases the integration branch on it with a
    conflict resolution protocol, then creates a task branch.
  - `browser` (`/browser`): drives a local debug Chrome.
  - `prompt-architect`: turns a rough request into an engineered prompt that
    is grounded in the real files of the repository, with evals.
  - `video-director`: a video production pipeline from a brief to an edit
    hand-off.
- `settings-fragment.json`: the plugins that every instance gets. Claude Code
  installs them at startup through `extraKnownMarketplaces` and
  `enabledPlugins`:
  - `ponytail`: a minimal-code ruleset.
  - `caveman`: a terse output mode (off until you run `/caveman`).
  - `frontend-design`: UI generation (official).
  - `context7`: library docs on demand (official).
  - `superpowers`: a plan, spec and test workflow (official).
- `bootstrap.sh` and `merge-settings.js`: a one-step setup for one config
  directory.

## Setup

Requires git and Node.js.

```sh
git clone https://github.com/badman-returns/claude-kit.git
cd claude-kit
./bootstrap.sh                   # sets up $CLAUDE_CONFIG_DIR, else ~/.claude
./bootstrap.sh ~/.claude-work    # any other config directory
```

Restart Claude Code after the setup. The plugins download and install
automatically. The script keeps the previous `settings.json` as
`settings.json.bak`, and it never replaces a real skill directory that is
already in place.

## Updating

- **Change a skill:** edit it here, commit and push. On other machines, run
  `git pull`. The skills are symlinks, so the pull is the update.
- **Add or remove a plugin:** edit `settings-fragment.json`, then run
  `./bootstrap.sh` again for each config directory. To turn a plugin off for
  one instance only, set its entry to `false` in that instance's
  `settings.json`.

## Notes

- The skills are symlinks, not copies. Keep this clone in a location that
  does not move.
- Plugin skills from a marketplace have a namespace (for example
  `/ponytail`). The custom skills keep their plain names (`/task-start`).
- [graphify](https://github.com/safishamsi/graphify) (any input to a
  knowledge graph) is a skill that I also use. It is not in this kit: install
  it from its own project.

## Related

- [watchkeeper](https://github.com/badman-returns/watchkeeper): a read-only
  viewer for every repository and worktree on one machine, made to review the
  work of coding agents.
- [janus](https://github.com/badman-returns/janus): an agentic delivery
  workflow as a Claude Code plugin, with architect, builder, reviewer and
  verifier agents and two human approval gates.
- [bosun](https://github.com/badman-returns/bosun): my agent-fleet setup.

## License

MIT. See [LICENSE](LICENSE).

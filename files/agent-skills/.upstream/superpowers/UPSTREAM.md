# superpowers: upstream

- Source: https://github.com/obra/superpowers, folder `skills/`
- Release: v7.0.2, commit `22f0b463e7a5e579904dd6211a520321035526f7` (2026-11-03)
- License: MIT (`LICENSE` next to this file; Copyright (c) Jesse Vincent, as in upstream's license file).
- Local changes: none. All 15 skill folders are byte-for-byte copies, and they are identical to the
  v7.0.2 Claude Code plugin (`superpowers@claude-plugins-official`) that was installed when they were copied.

Skills copied: brainstorming, diagnosing-superpowers, dispatching-parallel-agents, executing-plans,
finishing-a-development-branch, receiving-code-review, requesting-code-review, subagent-driven-development,
systematic-debugging, test-driven-development, using-git-worktrees, using-superpowers,
verification-before-completion, writing-plans, writing-skills.

Not copied: the plugin's `hooks/` (the SessionStart hook that loads `using-superpowers` at startup), `agents/`,
tests and docs. Skills alone are chosen by their descriptions; nothing loads them at startup.

## Things to know

- **Plugin overlap.** With the plugin still installed, Claude sees each skill twice (`superpowers:<name>` and
  `<name>`). Uninstall the plugin once these links are live (`/plugin uninstall superpowers@claude-plugins-official`).
- **Names.** Skills refer to each other as `superpowers:<name>`. Here the names are bare (`<name>`).
- **Scripts.** Skills run bundled scripts by absolute path with `bash`/`node`: `brainstorming/scripts/`,
  `executing-plans/scripts/`, `subagent-driven-development/scripts/`, `systematic-debugging/find-polluter.sh`,
  `writing-skills/render-graphs.js`. They need `bash`, `node` (brainstorming server) and `git`.
- **brainstorming** starts a local web server on 127.0.0.1 (random port, access key). The served page loads a logo
  from primeradiant.com. It opens a browser only if started with `--open`. With `--project-dir` it writes session files under
  `<project>/.superpowers/brainstorm/`.
- **git rules.** `writing-plans` and `finishing-a-development-branch` tell the agent to `git add`, `git commit`
  and `git push`. In this repo `CLAUDE.md` forbids those, and that rule wins.
- **diagnosing-superpowers** can file a GitHub issue on obra/superpowers (`gh issue create`) from a session
  report, after redaction. It only runs when the user asks.

## Updating

Copy `skills/` from a fresh clone (or the new plugin version), read the diff, then update the release above.

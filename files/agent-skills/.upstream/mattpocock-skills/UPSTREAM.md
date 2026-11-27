# mattpocock-skills: upstream

- Source: https://github.com/mattpocock/skills, folders `skills/engineering/` and `skills/productivity/`
- Commit: `6f7f7831a625f040a8e06a0e7954826b87ce775a` (2026-11-25)
- License: MIT, Copyright (c) 2026 Matt Pocock (`LICENSE` next to this file).
- Local changes: none. Every folder is a byte-for-byte copy of the upstream folder, including `agents/openai.yaml`.

Skills copied: every skill in the promoted buckets `skills/engineering/` and `skills/productivity/`, which is the set
upstream ships in its Claude Code plugin (`.claude-plugin/plugin.json`):

- engineering: ask-matt, code-review, codebase-design, diagnosing-bugs, domain-modeling, grill-with-docs, implement,
  implement-spec, improve-codebase-architecture, pr, prototype, research, retro, setup-matt-pocock-skills, tdd,
  to-spec, to-tickets, triage, wayfinder, wizard.
- productivity: grill-me, grilling, handoff, teach, to-questionnaire, wait-what, writing-for-agents.

`grilling` and `grill-me` keep their own `UPSTREAM.md` (commit `5863806`, content identical to this commit).

Not copied: `skills/in-progress/` (upstream marks them beta and leaves them out of its plugin), `skills/misc/` (kept
upstream but "rarely used, not promoted") and `skills/deprecated/`.

## Things to know

- **Names.** `code-review` has the same name as Claude Code's built-in `/code-review`. Check which one wins when
  you invoke it.
- **Manual-only skills.** `ask-matt`, `grill-with-docs`, `grill-me`, `handoff`, `implement`, `implement-spec`,
  `improve-codebase-architecture`, `retro`, `setup-matt-pocock-skills`, `teach`, `to-questionnaire`, `to-spec`,
  `to-tickets`, `triage`, `wait-what` and `wayfinder` set `disable-model-invocation: true`. They only run when you
  type the command.
- **Setup first.** `to-spec`, `to-tickets` and `code-review` expect the issue tracker settings that
  `/setup-matt-pocock-skills` writes into a repo's `CLAUDE.md`/`AGENTS.md` and `docs/agents/`. Run it once per repo.
- **git rules.** `implement` (and other skills that commit or open PRs, such as `pr`) ends with "Commit your work to the current branch". In this repo `CLAUDE.md` forbids
  `git commit`, and that rule wins.
- **Scripts.** Only `wizard` bundles one (`template.sh`, the library for the bash wizards it generates). It runs only
  when you use that skill.

## Updating

Copy the folders from a fresh clone, read the diff, then update the commit above.
